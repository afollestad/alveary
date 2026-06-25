@preconcurrency import AppKit
import Carbon
import SwiftUI

struct AppShotShortcutRecorder: View {
    @Binding var shortcut: AppShotKeyboardShortcut

    @State private var message: AppShotShortcutRecorderMessage?

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 10) {
                AppShotShortcutRecorderButton(
                    shortcut: $shortcut,
                    message: $message
                )
                .frame(width: 150, height: SettingsScreenLayout.settingsControlSurfaceHeight)

                Button("Use Default") {
                    shortcut = AppSettings.defaultAppShotShortcut
                    message = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(shortcut == AppSettings.defaultAppShotShortcut)
                .help("Restores the default app-shot shortcut.")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            if let message {
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(message.style)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("App shot shortcut")
        .accessibilityValue(shortcut.displayString)
    }
}

private struct AppShotShortcutRecorderButton: NSViewRepresentable {
    @Binding var shortcut: AppShotKeyboardShortcut
    @Binding var message: AppShotShortcutRecorderMessage?

    func makeCoordinator() -> Coordinator {
        Coordinator(shortcut: $shortcut, message: $message)
    }

    func makeNSView(context: Context) -> AppShotShortcutRecorderButtonView {
        let button = AppShotShortcutRecorderButtonView()
        button.onShortcutRecorded = { shortcut in
            context.coordinator.record(shortcut)
        }
        button.onRecordingStateReset = {
            context.coordinator.clearMessage()
        }
        button.onValidationError = { message in
            context.coordinator.showValidationMessage(message)
        }
        return button
    }

    func updateNSView(_ button: AppShotShortcutRecorderButtonView, context: Context) {
        context.coordinator.shortcut = $shortcut
        context.coordinator.message = $message
        button.currentShortcut = shortcut
        button.currentValidationShortcut = shortcut
    }

    @MainActor
    final class Coordinator {
        var shortcut: Binding<AppShotKeyboardShortcut>
        var message: Binding<AppShotShortcutRecorderMessage?>

        init(
            shortcut: Binding<AppShotKeyboardShortcut>,
            message: Binding<AppShotShortcutRecorderMessage?>
        ) {
            self.shortcut = shortcut
            self.message = message
        }

        func record(_ recordedShortcut: AppShotKeyboardShortcut) {
            shortcut.wrappedValue = recordedShortcut
            message.wrappedValue = nil
        }

        func showValidationMessage(_ text: String) {
            message.wrappedValue = .warning(text)
        }

        func clearMessage() {
            message.wrappedValue = nil
        }
    }
}

@MainActor
private final class AppShotShortcutRecorderButtonView: NSButton {
    var currentShortcut: AppShotKeyboardShortcut? {
        didSet {
            updateTitle()
        }
    }
    var currentValidationShortcut: AppShotKeyboardShortcut?
    var onShortcutRecorded: ((AppShotKeyboardShortcut) -> Void)?
    var onRecordingStateReset: (() -> Void)?
    var onValidationError: ((String) -> Void)?

    private var isRecording = false

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
        setAccessibilityLabel("App shot keyboard shortcut")
        setAccessibilityHelp("Records the global keyboard shortcut used to capture an app shot.")
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

        guard let shortcut = AppShotKeyboardShortcut.recorded(from: event) else {
            showValidationMessage("Use at least two modifier keys.")
            return
        }
        if let message = AppShotKeyboardShortcut.validationMessage(
            for: shortcut,
            currentShortcut: currentValidationShortcut ?? AppSettings.defaultAppShotShortcut
        ) {
            showValidationMessage(message)
            return
        }

        finishRecording()
        currentShortcut = shortcut
        onShortcutRecorded?(shortcut)
    }

    private func isCancelEvent(_ event: NSEvent) -> Bool {
        let modifiers = AppShotKeyboardShortcutModifiers(event.modifierFlags)
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
        let shortcutTitle = currentShortcut?.displayString
        title = shortcutTitle ?? "Record"
        setAccessibilityValue(shortcutTitle)
    }
}

struct AppShotShortcutRecorderMessage: Equatable {
    let text: String
    let style: Color

    static func warning(_ text: String) -> AppShotShortcutRecorderMessage {
        AppShotShortcutRecorderMessage(text: text, style: .orange)
    }
}
