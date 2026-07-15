import AppKit
import ApplicationServices
import CoreGraphics
import VoiceCodexCore

/// Delivers dictation to the focused field of the last external application.
///
/// Electron apps such as VS Code often expose their chat editors as generic
/// accessibility groups rather than `AXTextField` elements. Sending a real
/// paste event to the application after it has become active is therefore more
/// reliable than rejecting those fields through an AX-role check.
final class FocusedInputAccessibilityController: NSObject, CodexChatControlling {
    private let ownBundleIdentifier = "local.voicecodex.assistant"
    private let vsCodeBundleIdentifiers: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders"
    ]
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
        _ = try await activateTargetApplication()
        try paste(prompt)
    }

    func submit() async throws {
        let application = try await activateTargetApplication()

        // The Codex/Chat input in Electron can deliberately map Return to a
        // newline. Prefer its exposed Send button, which invokes the same
        // action as a mouse click and is independent of user keybindings.
        if pressSubmitButton(in: application) { return }

        // In VS Code, Cmd+Return is the alternate chat-submit shortcut. It is
        // deliberately used only after the button lookup failed; sending a
        // plain Return first could insert an unwanted line break instead.
        if let identifier = lastExternalApplication?.bundleIdentifier,
           vsCodeBundleIdentifiers.contains(identifier) {
            try postKey(keyCode: 36, flags: .maskCommand) // Cmd+Return
        } else {
            try postKey(keyCode: 36) // Return for normal text inputs
        }
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
        let application = try await activateTargetApplication()
        if let input = focusedEditableElement(in: application) {
            try focus(input)
            lastInput = input
        }
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

        let application = try await activateTargetApplication()
        for _ in 0..<12 {
            if let input = focusedEditableElement(in: application) { return input }
            try? await Task.sleep(for: .milliseconds(100))
        }
        throw FocusedInputFailure.inputNotFound
    }

    private func activateTargetApplication() async throws -> AXUIElement {
        if lastExternalApplication?.isTerminated == true {
            lastExternalApplication = nil
        }
        guard AXIsProcessTrusted() else { throw FocusedInputFailure.accessibilityPermissionMissing }
        guard let application = lastExternalApplication ?? NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier != ownBundleIdentifier else {
            throw FocusedInputFailure.noTargetApplication
        }
        application.activate()
        // App activation is asynchronous. Without this short delay the paste
        // event can land in Voice Codex instead of VS Code.
        try await Task.sleep(for: .milliseconds(180))
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

    /// Finds the chat's visible send action near the current focus and invokes
    /// it through AXPress. This works for Codex/Copilot webviews even when the
    /// input itself is exposed as an accessibility group instead of a text
    /// field.
    private func pressSubmitButton(in application: AXUIElement) -> Bool {
        var scopes: [AXUIElement] = []
        if let focused = focusedElement(in: application) {
            var element: AXUIElement? = focused
            for _ in 0..<5 {
                guard let current = element else { break }
                scopes.append(current)
                element = parent(of: current)
            }
        }
        scopes.append(application)

        for scope in scopes {
            if let button = findSubmitButton(in: scope, maximumDepth: 5),
               AXUIElementPerformAction(button, kAXPressAction as CFString) == .success {
                return true
            }
        }
        return false
    }

    private func focusedElement(in root: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value else { return nil }
        return value as! AXUIElement
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              let value else { return nil }
        return value as! AXUIElement
    }

    private func findSubmitButton(in root: AXUIElement, maximumDepth: Int) -> AXUIElement? {
        var visited = 0
        func visit(_ element: AXUIElement, depth: Int) -> AXUIElement? {
            guard depth <= maximumDepth, visited < 500 else { return nil }
            visited += 1
            if isSubmitButton(element) { return element }

            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
                  let children = value as? [AXUIElement] else { return nil }
            for child in children {
                if let result = visit(child, depth: depth + 1) { return result }
            }
            return nil
        }
        return visit(root, depth: 0)
    }

    private func isSubmitButton(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
              role as? String == kAXButtonRole else { return false }

        let labels = [
            kAXTitleAttribute as String,
            kAXDescriptionAttribute as String,
            kAXHelpAttribute as String,
            kAXIdentifierAttribute as String
        ].compactMap { attribute -> String? in
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
                return nil
            }
            return value as? String
        }.joined(separator: " ").lowercased()

        guard !labels.contains("feedback") else { return false }
        return [
            "send", "submit", "send message", "send chat", "send request",
            "absenden", "senden", "nachricht senden", "anfrage senden"
        ].contains { labels.contains($0) }
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
