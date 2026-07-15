import AppKit
import SwiftUI
import VoiceCodexCore

@main
struct VoiceCodexApp: App {
    @StateObject private var runtime = AssistantRuntime()

    var body: some Scene {
        WindowGroup("Voice Codex") {
            VoiceCodexControlView(runtime: runtime)
        }
        .defaultSize(width: 440, height: 650)
        .windowResizability(.contentSize)

        MenuBarExtra("Voice Codex", systemImage: runtime.symbolName) {
            VStack(alignment: .leading, spacing: 10) {
                Text(runtime.status).font(.headline)
                if !runtime.lastTranscription.isEmpty {
                    Text(runtime.lastTranscription)
                        .font(.caption)
                        .lineLimit(3)
                        .foregroundStyle(.secondary)
                }
                Divider()
                Button(runtime.isRunning ? "Aufnahme stoppen" : "Aufnahme starten") {
                    runtime.isRunning ? runtime.stop() : runtime.start()
                }
                SettingsLink {
                    Text("Voice Codex öffnen")
                }
                Button("Bedienungshilfen freigeben") { runtime.requestAccessibilityAccess() }
                Divider()
                Button("Voice Codex beenden") { NSApplication.shared.terminate(nil) }
            }
            .padding(12)
            .frame(width: 280)
        }

        Settings {
            VoiceCodexControlView(runtime: runtime)
        }
    }
}

@MainActor
final class AssistantRuntime: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Ready"
    @Published private(set) var lastTranscription = ""
    @Published private(set) var currentDraft = ""
    @Published private(set) var microphoneActivity = "Mikrofon aus"
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var accessibilityIsGranted = AXIsProcessTrusted()

    private let commandParser = CommandParser()
    private let wakeTranscriber = AppleSpeechTranscriber()
    private let promptTranscriber = HandyCLITranscriber()
    private let inputController: FocusedInputAccessibilityController
    private let session: AssistantSession
    private var wakeUsesHandy = false
    private var isTransitioning = false
    private var receivedWakeRecognition = false
    private var wakeSpeechWatchdog: Task<Void, Never>?

    var symbolName: String { isRunning ? "waveform.circle.fill" : "waveform.circle" }

    init() {
        let controller = FocusedInputAccessibilityController()
        inputController = controller
        session = AssistantSession(chat: controller)
        promptTranscriber.onActivity = { [weak self] activity in
            Task { @MainActor [weak self] in
                self?.microphoneActivity = activity
            }
        }
        promptTranscriber.onAudioLevel = { [weak self] level in
            Task { @MainActor [weak self] in
                self?.audioLevel = min(level * 25, 1)
            }
        }
    }

    func testTargetInput() {
        Task {
            status = "Suche zuletzt aktives Eingabefeld..."
            do {
                try await inputController.testTarget()
                status = "Ziel-Eingabefeld erkannt und fokussiert."
            } catch {
                status = "Eingabefeld-Test fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    func start() {
        guard !isRunning else { return }
        Task { await startAfterPermissions() }
    }

    private func startAfterPermissions() async {
        guard !isRunning else { return }
        refreshAccessibilityPermission()
        status = "Mikrofonzugriff wird geprueft..."
        do {
            try await AppleSpeechTranscriber.requestMicrophoneAccess()
        } catch {
            status = error.localizedDescription
            return
        }

        isRunning = true
        microphoneActivity = "Mikrofon aktiv – Initialisierung"
        status = accessibilityIsGranted
            ? "Wake-Erkennung wird gestartet..."
            : "Wake-Erkennung wird gestartet... (VS-Code-Submit braucht noch Bedienungshilfen)"
        await startWakeListening()
    }

    func stop() {
        Task {
            await wakeTranscriber.stop()
            await promptTranscriber.stop()
        }
        wakeSpeechWatchdog?.cancel()
        wakeSpeechWatchdog = nil
        isRunning = false
        isTransitioning = false
        status = "Gestoppt"
        lastTranscription = ""
        currentDraft = ""
        microphoneActivity = "Mikrofon aus"
        audioLevel = 0
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func requestAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        refreshAccessibilityPermission()
        if !accessibilityIsGranted {
            if !isRunning {
                status = "Bedienungshilfen bitte fuer Voice Codex erlauben."
            }
            openAccessibilitySettings()
            Task { await waitForAccessibilityRefresh() }
        }
    }

    private func refreshAccessibilityPermission() {
        accessibilityIsGranted = AXIsProcessTrusted()
    }

    private func waitForAccessibilityRefresh() async {
        for _ in 0..<60 {
            guard !accessibilityIsGranted else { return }
            try? await Task.sleep(for: .seconds(1))
            refreshAccessibilityPermission()
        }
    }

    private func label(for state: AssistantState) -> String {
        switch state {
        case .waiting: "Warte lokal auf ‘Codex’"
        case .dictating: "Prompt wird aufgenommen — sage ‘Submit’ oder ‘Absenden’"
        case .sleeping: "Schlafmodus"
        }
    }

    private func startWakeListening() async {
        guard isRunning, !isTransitioning else { return }
        status = "Warte lokal auf ‘Codex’ oder ‘Test’"
        microphoneActivity = "Mikrofon aktiv – sage ‘Codex’ oder ‘Test’"
        lastTranscription = ""
        currentDraft = ""
        wakeUsesHandy = true
        receivedWakeRecognition = false
        wakeSpeechWatchdog?.cancel()
        await startHandyWakeMode()
    }

    private func startHandyWakeMode() async {
        guard isRunning, !isTransitioning else { return }
        wakeSpeechWatchdog?.cancel()
        wakeSpeechWatchdog = nil
        wakeUsesHandy = true
        status = "Handy-Lokalmodell wird gestartet..."
        do {
            try await promptTranscriber.start { [weak self] text, isFinal in
                Task { @MainActor [weak self] in
                    await self?.handleWakeTranscript(text, isFinal: isFinal)
                }
            }
            status = "Warte lokal mit Handy auf ‘Codex’ oder ‘Test’"
        } catch {
            isRunning = false
            status = "Start fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func handleWakeTranscript(_ text: String, isFinal: Bool) async {
        guard isRunning, !isTransitioning else { return }
        receivedWakeRecognition = true
        wakeSpeechWatchdog?.cancel()
        wakeSpeechWatchdog = nil
        lastTranscription = text
        let command = commandParser.parse(text, in: .waiting)
        if command == .sleep {
            await promptTranscriber.stop()
            isRunning = false
            microphoneActivity = "Mikrofon aus"
            audioLevel = 0
            status = "Voice Codex beendet"
            return
        }
        guard command == .wake else { return }
        isTransitioning = true
        await stopWakeListening()

        do {
            try await session.receive(transcript: "Codex", isFinal: true)
            status = "Codex erkannt — Prompt wird gestartet…"
            try await promptTranscriber.start { [weak self] text, isFinal in
                Task { @MainActor [weak self] in
                    await self?.handlePromptTranscript(text, isFinal: isFinal)
                }
            }
            isTransitioning = false
            status = "Prompt wird aufgenommen — sage ‘Submit’ oder ‘Absenden’"
        } catch {
            isTransitioning = false
            isRunning = false
            status = "Prompt-Start fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func handlePromptTranscript(_ text: String, isFinal: Bool) async {
        guard isRunning, !isTransitioning else { return }
        lastTranscription = text
        guard isFinal else { return }
        do {
            try await session.receive(transcript: text, isFinal: true)
            let state = await session.state
            currentDraft = await session.draft
            status = label(for: state)
            guard state != .dictating else { return }

            isTransitioning = true
            await promptTranscriber.stop()
            isTransitioning = false
            if state == .waiting, isRunning {
                await startWakeListening()
            } else if state == .sleeping {
                isRunning = false
                microphoneActivity = "Mikrofon aus"
                audioLevel = 0
                status = "Voice Codex beendet"
            }
        } catch AssistantError.noPromptToSubmit {
            status = "Noch kein Prompt zum Absenden"
        } catch {
            status = "VS-Code-Befehl fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func stopWakeListening() async {
        wakeSpeechWatchdog?.cancel()
        wakeSpeechWatchdog = nil
        if wakeUsesHandy {
            await promptTranscriber.stop()
        } else {
            await wakeTranscriber.stop()
        }
    }
}
