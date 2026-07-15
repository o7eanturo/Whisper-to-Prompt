import Testing
@testable import VoiceCodexCore

struct CommandParserTests {
    @Test func recognizesWakeWordCaseAndPunctuationInsensitively() {
        #expect(CommandParser().parse("  Codéx! ", in: .waiting) == .wake)
    }

    @Test func recognizesCommonGermanWakeWordTranscriptions() {
        let parser = CommandParser()
        #expect(parser.parse("Codext", in: .waiting) == .wake)
        #expect(parser.parse("Kodex", in: .waiting) == .wake)
        #expect(parser.parse("hey Codex", in: .waiting) == .wake)
        #expect(parser.parse("Test", in: .waiting) == .wake)
    }

    @Test func preservesNormalDictation() {
        #expect(CommandParser().parse("Erstelle einen Dashboard Header", in: .dictating) == .dictation("Erstelle einen Dashboard Header"))
    }

    @Test func recognizesSubmit() {
        #expect(CommandParser().parse("Submit.", in: .dictating) == .submit)
    }
}
