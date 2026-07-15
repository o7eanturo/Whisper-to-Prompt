import Foundation

public struct CommandParser: Sendable {
    private let configuration: AssistantConfiguration
    // German speech recognition often turns the product name into one of
    // these variants. Keeping this list explicit avoids a fuzzy matcher that
    // could accidentally wake the assistant during normal conversation.
    private let wakeAliases: Set<String> = [
        "codex", "codext", "codexx", "codexs", "codec", "codecs",
        "kodex", "kodext", "kodexx", "kodexs",
        "test", "teste", "start", "starte"
    ]

    public init(configuration: AssistantConfiguration = .init()) {
        self.configuration = configuration
    }

    public func parse(_ transcript: String, in state: AssistantState) -> VoiceCommand {
        let normalized = normalize(transcript)
        guard !normalized.isEmpty else { return .dictation("") }

        if configuration.wakeWords.contains(normalized) || normalized.split(separator: " ").contains(where: { token in
            configuration.wakeWords.contains(String(token)) || wakeAliases.contains(String(token))
        }) { return .wake }
        if let command = configuration.commandWords[normalized] { return command }
        return .dictation(transcript.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
