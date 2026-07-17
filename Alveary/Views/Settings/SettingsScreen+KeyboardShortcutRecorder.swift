@preconcurrency import AppKit
import Carbon
import SwiftUI

struct PhysicalKeyboardShortcutRecorderButton: NSViewRepresentable {
    let currentShortcut: PhysicalKeyboardShortcut?
    let displayString: String?
    let accessibilityLabel: String
    let accessibilityHelp: String
    var allowsModifierKey = false
    var invalidShortcutMessage = "Press a nonmodifier key with at least two modifier keys."
    var recordedShortcutDisplay: (PhysicalKeyboardShortcut) -> String = { $0.displayString }
    let validate: (PhysicalKeyboardShortcut) -> String?
    let onShortcutRecorded: (PhysicalKeyboardShortcut) -> Void
    let onRecordingStateReset: () -> Void
    let onValidationError: (String) -> Void

    func makeNSView(context: Context) -> PhysicalShortcutRecorderButtonView {
        PhysicalShortcutRecorderButtonView()
    }

    func updateNSView(_ button: PhysicalShortcutRecorderButtonView, context: Context) {
        button.currentShortcut = currentShortcut
        button.currentDisplayString = displayString
        button.allowsModifierKey = allowsModifierKey
        button.invalidShortcutMessage = invalidShortcutMessage
        button.recordedShortcutDisplay = recordedShortcutDisplay
        button.onShortcutRecorded = onShortcutRecorded
        button.onRecordingStateReset = onRecordingStateReset
        button.onValidationError = onValidationError
        button.validate = validate
        button.isEnabled = context.environment.isEnabled
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityHelp(accessibilityHelp)
    }
}

@MainActor
final class PhysicalShortcutRecorderButtonView: NSButton {
    var currentShortcut: PhysicalKeyboardShortcut? {
        didSet {
            updateTitle()
        }
    }
    var currentDisplayString: String? {
        didSet {
            updateTitle()
        }
    }
    var onShortcutRecorded: ((PhysicalKeyboardShortcut) -> Void)?
    var onRecordingStateReset: (() -> Void)?
    var onValidationError: ((String) -> Void)?
    var validate: ((PhysicalKeyboardShortcut) -> String?)?
    var allowsModifierKey = false
    var invalidShortcutMessage = "Press a nonmodifier key with at least two modifier keys."
    var recordedShortcutDisplay: (PhysicalKeyboardShortcut) -> String = { $0.displayString }

    private(set) var isRecording = false

    override var acceptsFirstResponder: Bool {
        true
    }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(startRecording)
        focusRingType = .default
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        handleShortcutEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }
        handleShortcutEvent(event)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard !isRecording else {
            return
        }
        super.flagsChanged(with: event)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            finishRecording()
            onRecordingStateReset?()
        }
        return super.resignFirstResponder()
    }

    @objc private func startRecording() {
        guard isEnabled else {
            return
        }
        isRecording = true
        title = "Press Shortcut"
        onRecordingStateReset?()
        window?.makeFirstResponder(self)
    }

    private func handleShortcutEvent(_ event: NSEvent) {
        if isCancelEvent(event) {
            finishRecording()
            onRecordingStateReset?()
            return
        }

        guard let shortcut = PhysicalKeyboardShortcut.recorded(
            from: event,
            allowsModifierKey: allowsModifierKey
        ) else {
            showValidationMessage(invalidShortcutMessage)
            return
        }
        if let message = validate?(shortcut) {
            showValidationMessage(message)
            return
        }

        let displayString = recordedShortcutDisplay(shortcut)
        finishRecording()
        currentDisplayString = displayString
        currentShortcut = shortcut
        onShortcutRecorded?(shortcut)
    }

    private func isCancelEvent(_ event: NSEvent) -> Bool {
        let modifiers = PhysicalKeyboardShortcutModifiers(event.modifierFlags)
        return event.keyCode == UInt16(kVK_Escape) && modifiers.isEmpty
    }

    private func finishRecording() {
        isRecording = false
        updateTitle()
    }

    private func showValidationMessage(_ message: String) {
        NSSound.beep()
        onValidationError?(message)
    }

    private func updateTitle() {
        guard !isRecording else {
            return
        }
        let shortcutTitle = currentDisplayString ?? currentShortcut?.displayString
        title = shortcutTitle ?? "Record"
        setAccessibilityValue(shortcutTitle)
    }
}

struct KeyboardShortcutRecorderMessage: Equatable {
    let text: String
    let style: Color

    static func warning(_ text: String) -> KeyboardShortcutRecorderMessage {
        KeyboardShortcutRecorderMessage(text: text, style: .orange)
    }
}
