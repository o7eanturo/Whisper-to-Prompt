import Foundation

public actor AssistantSession {
    public private(set) var state: AssistantState = .waiting
    public private(set) var draft = ""

    private let parser: CommandParser
    private let chat: CodexChatControlling

    public init(parser: CommandParser = .init(), chat: CodexChatControlling) {
        self.parser = parser
        self.chat = chat
    }

    public func receive(transcript: String, isFinal: Bool) async throws {
        // Partial recognition results are intentionally ignored: this prevents
        // a command from firing while the user is still speaking.
        guard isFinal else { return }
        let command = parser.parse(transcript, in: state)

        switch (state, command) {
        case (.sleeping, .wakeUp), (.waiting, .wake):
            state = .dictating
        case (_, .sleep):
            reset(to: .sleeping)
        case (.dictating, .dictation(let text)) where !text.isEmpty:
            append(text)
        case (.dictating, .clear):
            draft = ""
            try await chat.clear()
        case (.dictating, .cancel), (.dictating, .stop):
            reset(to: .waiting)
        case (.dictating, .finish):
            guard !draft.isEmpty else { throw AssistantError.noPromptToSubmit }
            try await chat.insert(prompt: draft)
            reset(to: .waiting)
        case (.dictating, .submit):
            guard !draft.isEmpty else { throw AssistantError.noPromptToSubmit }
            try await chat.insert(prompt: draft)
            try await chat.submit()
            reset(to: .waiting)
        case (.dictating, .continue):
            try await chat.continueConversation()
        default:
            break
        }
    }

    private func append(_ text: String) {
        draft = draft.isEmpty ? text : "\(draft) \(text)"
    }

    private func reset(to newState: AssistantState) {
        draft = ""
        state = newState
    }
}
