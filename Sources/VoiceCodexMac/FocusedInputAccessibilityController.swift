import AppKit
import ApplicationServices
import CoreGraphics
import VoiceCodexCore

/// Pastes dictation into the input field that was active immediately before
/// Voice Codex became active. This mirrors the behaviour of desktop dictation
/// tools and works with VS Code, browsers, terminals, and native text fields.
final class FocusedInputAccessibilityController: NSObject, CodexChatControlling {
    private let ownBundleIdentifier = "local.voicecodex.assistant"
    private var lastExternalApplication: NSRunningApplication?
    private var lastInput: AXUIElement?

    override init() {
        super.init()
        rememberCurrentExternalApplication()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func insert(prompt: String) async throws {
        let input = try await locateTargetInput()
        try focus(input)
        try paste(prompt)
        lastInput = input
        try await Task.sleep(for: .milliseconds(120))
    }

    func submit() async throws {
        let input = try await locateTargetInput(preferRememberedInput: true)
        try focus(input)
        try postKey(keyCode: 36) // Return
    }

    func clear() async throws {
        let input = try await locateTargetInput()
        try focus(input)
        try postKey(keyCode: 0, flags: .maskCommand)
        try postKey(keyCode: 51)
    }

    func continueConversation() async throws {
        try await submit()
    }

    /// Focuses the remembered target without changing its contents.
    func testTarget() async throws {
        let input = try await locateTargetInput()
        try focus(input)
        lastInput = input
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier != ownBundleIdentifier,
              !app.isTerminated else { return }
        lastExternalApplication = app
    }

    private func rememberCurrentExternalApplication() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != ownBundleIdentifier else { return }
        lastExternalApplication = app
    }

    private func locateTargetInput(preferRememberedInput: Bool = false) async throws -> AXUIElement {
        guard AXIsProcessTrusted() else { throw FocusedInputFailure.accessibilityPermissionMissing }

        if preferRememberedInput, let lastInput {
            return lastInput
        }

        let application = try activateTargetApplication()
        for _ in 0..<12 {
            if let input = focusedEditableElement(in: application) { return input }
            try? await Task.sleep(for: .milliseconds(100))
        }
        throw FocusedInputFailure.inputNotFound
    }

    private func activateTargetApplication() throws -> AXUIElement {
        if lastExternalApplication?.isTerminated == true {
            lastExternalApplication = nil
        }
        guard let application = lastExternalApplication ?? NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier != ownBundleIdentifier else {
            throw FocusedInputFailure.noTargetApplication
        }
        application.activate()
        return AXUIElementCreateApplication(application.processIdentifier)
    }

    private func focusedEditableElement(in root: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let element = value else { return nil }
        let input = element as! AXUIElement
        return isEditable(input) ? input : nil
    }

    private func isEditable(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let roleName = role as? String ?? ""
        return [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(roleName)
    }

    private func focus(_ element: AXUIElement) throws {
        let result = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        if result != .success && result != .attributeUnsupported {
            throw FocusedInputFailure.cannotFocusInput
        }
    }

    private func paste(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw FocusedInputFailure.cannotWritePasteboard
        }
        try postKey(keyCode: 9, flags: .maskCommand) // Cmd+V
    }

    private func postKey(keyCode: CGKeyCode, flags: CGEventFlags = []) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw FocusedInputFailure.keyEventCreationFailed
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

enum FocusedInputFailure: Error, LocalizedError {
    case accessibilityPermissionMissing
    case noTargetApplication
    case inputNotFound
    case cannotFocusInput
    case cannotWritePasteboard
    case keyEventCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            "Bedienungshilfen fuer Voice Codex fehlen."
        case .noTargetApplication:
            "Kein Zielprogramm gefunden. Klicke zuerst in das gewünschte Eingabefeld und starte dann Voice Codex."
        case .inputNotFound:
            "Im Zielprogramm ist kein fokussiertes Eingabefeld vorhanden."
        case .cannotFocusInput:
            "Das Ziel-Eingabefeld konnte nicht fokussiert werden."
        case .cannotWritePasteboard:
            "Der Text konnte nicht in die Zwischenablage geschrieben werden."
        case .keyEventCreationFailed:
            "Tastatureingabe konnte nicht erzeugt werden."
        }
    }
}
