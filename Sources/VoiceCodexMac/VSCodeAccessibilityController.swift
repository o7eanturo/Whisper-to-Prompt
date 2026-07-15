import AppKit
import ApplicationServices
import CoreGraphics
import VoiceCodexCore

struct VSCodeConfiguration {
    let bundleIdentifiers = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]
    /// VS Code's `workbench.action.chat.open` default on macOS: Ctrl+Cmd+I.
    /// Keep this configurable because a user keybinding takes precedence.
    let chatFocusKeyCode: CGKeyCode = 34 // I
    let chatFocusModifiers: CGEventFlags = [.maskControl, .maskCommand]
}

final class VSCodeAccessibilityController: CodexChatControlling {
    private let configuration = VSCodeConfiguration()
    private var lastInput: AXUIElement?

    func insert(prompt: String) async throws {
        let application = try activateVSCode()
        let input = try await locatePromptInput(in: application)
        try focus(input)
        lastInput = input
        // Paste generates a real input event in Electron. AXValue alone can
        // update accessibility state without updating the Chat input model.
        try postKey(keyCode: 0, flags: .maskCommand) // Cmd+A
        try paste(prompt)
        try await Task.sleep(for: .milliseconds(120))
    }

    func submit() async throws {
        if let lastInput { try focus(lastInput) }
        try postKey(keyCode: 36) // Return
    }

    func clear() async throws {
        let application = try activateVSCode()
        let input = try await locatePromptInput(in: application)
        try focus(input)
        try postKey(keyCode: 0, flags: .maskCommand) // Cmd+A
        try postKey(keyCode: 51) // Delete
    }

    func continueConversation() async throws {
        let application = try activateVSCode()
        let input = try await locatePromptInput(in: application)
        try focus(input)
        try postKey(keyCode: 36)
    }

    /// Safe diagnostic used by the GUI: opens/focuses an input but never
    /// inserts or submits text.
    func testConnection() async throws {
        let application = try activateVSCode()
        let input = try await locatePromptInput(in: application)
        try focus(input)
        lastInput = input
    }

    private func activateVSCode() throws -> AXUIElement {
        guard AXIsProcessTrusted() else { throw VSCodeFailure.accessibilityPermissionMissing }
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            configuration.bundleIdentifiers.contains($0.bundleIdentifier ?? "")
        }) else { throw VSCodeFailure.notRunning }
        app.activate()
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    private func locatePromptInput(in application: AXUIElement) async throws -> AXUIElement {
        // If the user already left the Codex prompt focused, preserve that
        // exact field. This is the same paste-first strategy used by dictation
        // apps and works across Codex/Copilot/other VS Code chat extensions.
        if let focused = findEditableElement(in: application), isLikelyPromptField(focused) {
            return focused
        }

        // VS Code's built-in Chat command is a reliable fallback for the
        // standard Chat/Codex integration.
        try postKey(keyCode: configuration.chatFocusKeyCode, flags: configuration.chatFocusModifiers)
        if let input = await waitForEditableElement(in: application, requirePromptHint: false) {
            return input
        }

        // Some VS Code versions only expose the Chat command through the
        // command palette. This remains local and does not depend on a
        // specific extension's private API.
        try postKey(keyCode: 35, flags: [.maskCommand, .maskShift]) // Cmd+Shift+P
        try await Task.sleep(for: .milliseconds(150))
        try paste("Chat: Open Chat")
        try postKey(keyCode: 36)
        if let input = await waitForEditableElement(in: application, requirePromptHint: false) {
            return input
        }

        if let candidate = findPromptCandidate(in: application) {
            return candidate
        }
        throw VSCodeFailure.chatInputNotFound
    }

    private func findEditableElement(in root: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &value)
        if let focused = value {
            let element = focused as! AXUIElement
            if isEditable(element) { return element }
        }
        return nil
    }

    private func waitForEditableElement(in root: AXUIElement, requirePromptHint: Bool) async -> AXUIElement? {
        for _ in 0..<10 {
            if let element = findEditableElement(in: root), (!requirePromptHint || isLikelyPromptField(element)) {
                return element
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    private func findPromptCandidate(in root: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 12 else { return nil }
        if isEditable(root), isLikelyPromptField(root) { return root }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return nil }
        for child in children {
            if let result = findPromptCandidate(in: child, depth: depth + 1) { return result }
        }
        return nil
    }

    private func paste(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw VSCodeFailure.cannotWritePasteboard
        }
        try postKey(keyCode: 9, flags: .maskCommand) // Cmd+V
    }

    private func isEditable(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        return [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(role as? String ?? "")
    }

    private func isLikelyPromptField(_ element: AXUIElement) -> Bool {
        let attributes = [
            kAXTitleAttribute as String,
            kAXDescriptionAttribute as String,
            kAXHelpAttribute as String,
            kAXIdentifierAttribute as String
        ]
        let text = attributes.compactMap { attribute -> String? in
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
            return value as? String
        }.joined(separator: " ").lowercased()
        return ["chat", "codex", "copilot", "prompt", "ask", "message", "input"].contains { text.contains($0) }
    }

    private func focus(_ element: AXUIElement) throws {
        let result = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        if result != .success && result != .attributeUnsupported {
            throw VSCodeFailure.cannotFocusInput
        }
    }

    private func postKey(keyCode: CGKeyCode, flags: CGEventFlags = []) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw VSCodeFailure.keyEventCreationFailed
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

enum VSCodeFailure: Error, LocalizedError {
    case accessibilityPermissionMissing, notRunning, chatInputNotFound, keyEventCreationFailed
    case cannotWritePasteboard, cannotFocusInput

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            "Bedienungshilfen fuer Voice Codex fehlen."
        case .notRunning:
            "VS Code ist nicht geöffnet."
        case .chatInputNotFound:
            "Kein Chat-Promptfeld gefunden. Öffne einmal den Codex-Chat in VS Code und drücke dann erneut Submit."
        case .keyEventCreationFailed:
            "Tastatureingabe fuer VS Code konnte nicht erzeugt werden."
        case .cannotWritePasteboard:
            "Prompt konnte nicht in die Zwischenablage geschrieben werden."
        case .cannotFocusInput:
            "Das gefundene VS-Code-Eingabefeld konnte nicht fokussiert werden."
        }
    }
}
