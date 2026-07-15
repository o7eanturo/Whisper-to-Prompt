import Foundation
import WhisperKit
import VoiceCodexCore

/// Uses Handy's already installed local German speech model. Audio is captured
/// locally, written to a temporary WAV file, transcribed by Handy's local CLI,
/// and deleted immediately afterwards. No audio leaves this Mac.
final class HandyCLITranscriber: LiveTranscribing {
    private let handyExecutable = URL(fileURLWithPath: "/Applications/Handy.app/Contents/MacOS/handy")
    private let modelID = "handy-computer/nemotron-3.5-asr-streaming-0.6b-gguf/nemotron-3.5-asr-streaming-0.6b-Q8_0.gguf"
    // Laptop and headset microphones often deliver lower RMS values than the
    // default Whisper gate. Keep this low and let Handy reject non-speech.
    private let speechThreshold: Float = 0.002
    private let endOfTurnSilence: TimeInterval = 0.8
    private let maximumTurnSeconds: TimeInterval = 25

    private var audioProcessor: AudioProcessor?
    private var recordingContinuation: AsyncThrowingStream<[Float], Error>.Continuation?
    private var recordingTask: Task<Void, Never>?
    private var onHypothesis: (@Sendable (String, Bool) -> Void)?
    private var turnSamples: [Float] = []
    private var trailingSilence: TimeInterval = 0
    private var isListening = false
    private var hasReportedSpeechForTurn = false

    var onActivity: (@Sendable (String) -> Void)?
    var onAudioLevel: (@Sendable (Float) -> Void)?

    func start(onHypothesis: @escaping @Sendable (String, Bool) -> Void) async throws {
        guard !isListening else { return }
        guard FileManager.default.isExecutableFile(atPath: handyExecutable.path) else {
            throw HandyFailure.notInstalled
        }

        self.onHypothesis = onHypothesis
        let processor = AudioProcessor()
        let (stream, continuation) = processor.startStreamingRecordingLive()
        audioProcessor = processor
        recordingContinuation = continuation
        isListening = true
        onActivity?("Mikrofon aktiv – Handy-Lokalmodell bereit")

        recordingTask = Task { [weak self] in
            do {
                for try await samples in stream {
                    await self?.consume(samples)
                }
            } catch {
                self?.onActivity?("Mikrofonstream wurde beendet")
            }
        }
    }

    func stop() async {
        isListening = false
        recordingTask?.cancel()
        recordingTask = nil
        recordingContinuation?.finish()
        recordingContinuation = nil
        audioProcessor?.stopRecording()
        audioProcessor = nil
        turnSamples.removeAll(keepingCapacity: false)
        trailingSilence = 0
        hasReportedSpeechForTurn = false
        onHypothesis = nil
    }

    private func consume(_ samples: [Float]) async {
        guard isListening, !samples.isEmpty else { return }
        let seconds = Double(samples.count) / Double(WhisperKit.sampleRate)
        let level = rms(samples)
        onAudioLevel?(level)
        let isSpeech = level >= speechThreshold

        if isSpeech {
            if !hasReportedSpeechForTurn {
                hasReportedSpeechForTurn = true
                onActivity?("Stimme erkannt – warte auf kurze Sprechpause")
            }
            turnSamples.append(contentsOf: samples)
            trailingSilence = 0
        } else if !turnSamples.isEmpty {
            turnSamples.append(contentsOf: samples)
            trailingSilence += seconds
        }

        let maximumSamples = Int(maximumTurnSeconds * Double(WhisperKit.sampleRate))
        if turnSamples.count >= maximumSamples || trailingSilence >= endOfTurnSilence {
            await transcribeCurrentTurn()
        }
    }

    private func transcribeCurrentTurn() async {
        guard !turnSamples.isEmpty else { return }
        let samples = turnSamples
        turnSamples.removeAll(keepingCapacity: true)
        trailingSilence = 0
        hasReportedSpeechForTurn = false
        onActivity?("Handy transkribiert lokal …")

        do {
            let wavURL = try writeWAV(samples: samples)
            defer { try? FileManager.default.removeItem(at: wavURL) }
            let text = try await transcribeWithHandy(wavURL: wavURL)
            if !text.isEmpty { onHypothesis?(text, true) }
            onActivity?("Mikrofon aktiv – bereit")
        } catch {
            onActivity?("Handy-Transkription fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private func transcribeWithHandy(wavURL: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = handyExecutable
            process.arguments = [
                "--transcribe-file", wavURL.path,
                "--model", modelID,
                "--json"
            ]
            process.standardOutput = output
            process.standardError = errors
            process.terminationHandler = { process in
                let outputData = output.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    do {
                        let result = try JSONDecoder().decode(HandyResult.self, from: outputData)
                        continuation.resume(returning: result.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: errorData, encoding: .utf8) ?? "Unbekannter Handy-Fehler"
                    continuation.resume(throwing: HandyFailure.transcriptionFailed(message))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func writeWAV(samples: [Float]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-codex-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        var data = Data()
        let byteCount = UInt32(samples.count * MemoryLayout<Int16>.size)
        data.append("RIFF".data(using: .ascii)!)
        appendLittleEndian(UInt32(36) + byteCount, to: &data)
        data.append("WAVEfmt ".data(using: .ascii)!)
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt32(WhisperKit.sampleRate), to: &data)
        appendLittleEndian(UInt32(WhisperKit.sampleRate * 2), to: &data)
        appendLittleEndian(UInt16(2), to: &data)
        appendLittleEndian(UInt16(16), to: &data)
        data.append("data".data(using: .ascii)!)
        appendLittleEndian(byteCount, to: &data)

        for sample in samples {
            let clipped = max(-1, min(1, sample))
            appendLittleEndian(Int16(clipped * Float(Int16.max)), to: &data)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private func rms(_ samples: [Float]) -> Float {
        let meanSquare = samples.reduce(Float.zero) { $0 + $1 * $1 } / Float(samples.count)
        return sqrt(meanSquare)
    }
}

private struct HandyResult: Decodable {
    let text: String
}

enum HandyFailure: LocalizedError {
    case notInstalled
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Handy.app wurde nicht unter /Applications gefunden."
        case .transcriptionFailed(let message):
            "Handy konnte nicht transkribieren: \(message)"
        }
    }
}
