import Testing
@testable import VoiceCodexCore

struct AssistantSessionTests {
    @Test func wakeDictateSubmitInsertsSpeechTurnsLiveAndSubmitsOnce() async throws {
        let chat = SpyChatController()
        let session = AssistantSession(chat: chat)
        try await session.receive(transcript: "Codex", isFinal: true)
        try await session.receive(transcript: "Erstelle eine Komponente", isFinal: true)
        try await session.receive(transcript: "Submit", isFinal: true)

        #expect(await chat.insertedPrompts() == ["Erstelle eine Komponente"])
        #expect(await chat.submitCount() == 1)
        #expect(await session.state == .waiting)
    }

    @Test func overEndsDictationWithoutInsertingTheDraftAgain() async throws {
        let chat = SpyChatController()
        let session = AssistantSession(chat: chat)
        try await session.receive(transcript: "Codex", isFinal: true)
        try await session.receive(transcript: "Schreibe einen Test", isFinal: true)
        try await session.receive(transcript: "Over", isFinal: true)

        #expect(await chat.insertedPrompts() == ["Schreibe einen Test"])
        #expect(await chat.submitCount() == 0)
        #expect(await session.state == .waiting)
    }

    @Test func partialTextDoesNotTriggerWake() async throws {
        let chat = SpyChatController()
        let session = AssistantSession(chat: chat)
        try await session.receive(transcript: "Codex", isFinal: false)
        #expect(await session.state == .waiting)
    }
}

private actor SpyChatController: CodexChatControlling {
    private var prompts: [String] = []
    private var submissions = 0
    func insert(prompt: String) { prompts.append(prompt) }
    func submit() { submissions += 1 }
    func clear() {}
    func continueConversation() {}
    func insertedPrompts() -> [String] { prompts }
    func submitCount() -> Int { submissions }
}
