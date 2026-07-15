import AVFoundation
import Speech
import VoiceCodexCore

/// Development adapter. It explicitly refuses a network fallback.
final class AppleSpeechTranscriber: NSObject, LiveTranscribing {
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onHypothesis: (@Sendable (String, Bool) -> Void)?
    private var isListening = false

    static func requestMicrophoneAccess() async throws {
        let microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
        guard microphoneGranted else { throw SpeechFailure.microphoneDenied }
    }

    func start(onHypothesis: @escaping @Sendable (String, Bool) -> Void) async throws {
        try await authorize()
        guard recognizer?.isAvailable == true else {
            throw SpeechFailure.recognizerUnavailable
        }
        guard recognizer?.supportsOnDeviceRecognition == true else {
            throw SpeechFailure.onDeviceRecognitionUnavailable
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
        self.onHypothesis = onHypothesis
        isListening = true
        beginRecognitionTask()
    }

    func stop() async {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
        onHypothesis = nil
    }

    private func authorize() async throws {
        try await Self.requestMicrophoneAccess()
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { throw SpeechFailure.speechAuthorizationDenied }
    }

    private func beginRecognitionTask() {
        guard isListening else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request
        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.onHypothesis?(result.bestTranscription.formattedString, result.isFinal)
            }
            // Apple Speech sessions are finite. Recreating only the request
            // keeps the microphone tap alive while allowing the next command.
            if result?.isFinal == true || error != nil {
                DispatchQueue.main.async { [weak self] in self?.beginRecognitionTask() }
            }
        }
    }
}

enum SpeechFailure: Error {
    case microphoneDenied, speechAuthorizationDenied, recognizerUnavailable, onDeviceRecognitionUnavailable
}

extension SpeechFailure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Mikrofon-Zugriff fehlt. Bitte in Systemeinstellungen > Datenschutz & Sicherheit > Mikrofon erlauben."
        case .speechAuthorizationDenied:
            "Apple Speech ist nicht freigegeben. Ich nutze sonst Whisper als lokalen Fallback, brauche aber Mikrofonzugriff."
        case .recognizerUnavailable:
            "Apple Speech ist gerade nicht verfuegbar. Ich wechsle auf Whisper."
        case .onDeviceRecognitionUnavailable:
            "Lokale Apple-Speech-Erkennung fuer Deutsch ist nicht verfuegbar. Ich wechsle auf Whisper."
        }
    }
}
