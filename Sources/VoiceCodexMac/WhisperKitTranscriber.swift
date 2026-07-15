import Foundation
import WhisperKit
import VoiceCodexCore

/// Fully local streaming transcription. Whisper is invoked only after the
/// lightweight RMS gate sees a spoken turn followed by silence; audio is kept
/// in memory only for that turn and discarded immediately afterwards.
final class WhisperKitTranscriber: LiveTranscribing {
    private let model = "tiny"
    private let speechThreshold: Float = 0.015
    private let endOfTurnSilence: TimeInterval = 0.8
    private let maximumTurnSeconds: TimeInterval = 25

    private var whisperKit: WhisperKit?
    private var audioProcessor: (any AudioProcessing)?
    private var recordingContinuation: AsyncThrowingStream<[Float], Error>.Continuation?
    private var recordingTask: Task<Void, Never>?
    private var onHypothesis: (@Sendable (String, Bool) -> Void)?
    private var turnSamples: [Float] = []
    private var trailingSilence: TimeInterval = 0
    private var isListening = false
    private var hasReportedSpeechForTurn = false
    var onActivity: (@Sendable (String) -> Void)?

    func start(onHypothesis: @escaping @Sendable (String, Bool) -> Void) async throws {
        guard !isListening else { return }
        self.onHypothesis = onHypothesis

        // The first start downloads and Core-ML-specializes the selected model.
        // Later launches reuse the local WhisperKit/Core ML caches.
        let config = WhisperKitConfig(model: model, verbose: false, prewarm: true)
        let kit = try await WhisperKit(config)
        let processor = kit.audioProcessor
        let (stream, continuation) = processor.startStreamingRecordingLive()

        whisperKit = kit
        audioProcessor = processor
        recordingContinuation = continuation
        isListening = true
        recordingTask = Task { [weak self] in
            do {
                for try await samples in stream {
                    await self?.consume(samples)
                }
            } catch {
                print("Whisper microphone stream ended: \(error.localizedDescription)")
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
        whisperKit = nil
        turnSamples.removeAll(keepingCapacity: false)
        trailingSilence = 0
        hasReportedSpeechForTurn = false
        onHypothesis = nil
    }

    private func consume(_ samples: [Float]) async {
        guard isListening, !samples.isEmpty else { return }
        let seconds = Double(samples.count) / Double(WhisperKit.sampleRate)
        let isSpeech = rms(samples) >= speechThreshold

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
        guard !turnSamples.isEmpty, let whisperKit else { return }
        let samples = turnSamples
        turnSamples.removeAll(keepingCapacity: true)
        trailingSilence = 0
        hasReportedSpeechForTurn = false
        onActivity?("Sprache wird lokal transkribiert …")

        do {
            let options = DecodingOptions(language: "de", detectLanguage: false, withoutTimestamps: true)
            let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
            let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { onHypothesis?(text, true) }
            onActivity?("Mikrofon aktiv – bereit")
        } catch {
            onActivity?("Transkription fehlgeschlagen – bitte erneut sprechen")
            print("Whisper transcription failed: \(error.localizedDescription)")
        }
    }

    private func rms(_ samples: [Float]) -> Float {
        let meanSquare = samples.reduce(Float.zero) { $0 + $1 * $1 } / Float(samples.count)
        return sqrt(meanSquare)
    }
}
