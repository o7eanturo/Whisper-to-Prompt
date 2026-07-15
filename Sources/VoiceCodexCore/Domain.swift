import Foundation

public enum AssistantState: Equatable, Sendable {
    case waiting
    case dictating
    case sleeping
}

public enum VoiceCommand: Equatable, Sendable {
    case wake
    case finish
    case submit
    case `continue`
    case clear
    case stop
    case cancel
    case sleep
    case wakeUp
    case dictation(String)
}

public struct AssistantConfiguration: Sendable {
    public let wakeWords: [String]
    public let commandWords: [String: VoiceCommand]

    public init(
        wakeWords: [String] = ["codex", "test", "start"],
        commandWords: [String: VoiceCommand] = [
            "submit": .submit, "continue": .continue, "clear": .clear,
            "stop": .stop, "cancel": .cancel, "sleep": .sleep,
            "wake up": .wakeUp,
            "over": .finish, "end": .finish, "ende": .finish,
            "fertig": .finish, "beenden": .finish,
            "absenden": .submit, "abschicken": .submit, "senden": .submit,
            "bestatigen": .submit, "weiter": .continue, "leeren": .clear,
            "loschen": .clear, "stopp": .stop, "abbrechen": .cancel,
            "schlafen": .sleep, "aufwachen": .wakeUp, "exit": .sleep
        ]
    ) {
        self.wakeWords = wakeWords
        self.commandWords = commandWords
    }
}

public protocol LiveTranscribing: AnyObject {
    func start(onHypothesis: @escaping @Sendable (String, Bool) -> Void) async throws
    func stop() async
}

public protocol CodexChatControlling: AnyObject {
    func insert(prompt: String) async throws
    func submit() async throws
    func clear() async throws
    func continueConversation() async throws
}

public enum AssistantError: Error, Equatable {
    case noPromptToSubmit
}
