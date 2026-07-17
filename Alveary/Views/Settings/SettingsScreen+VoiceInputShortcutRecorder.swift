@preconcurrency import AppKit
import SwiftUI

struct VoiceInputShortcutRecorder: View {
    @Binding var shortcut: PhysicalKeyboardShortcut?
    let appShotShortcut: AppShotKeyboardShortcut
    let supportsVoiceInput: Bool

    @State private var message: KeyboardShortcutRecorderMessage?
    @State private var validationRevision = UUID()

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 10) {
                PhysicalKeyboardShortcutRecorderButton(
                    currentShortcut: shortcut,
                    displayString: shortcut?.displayString,
                    accessibilityLabel: "Voice input keyboard shortcut",
                    accessibilityHelp: "Records the app-local keyboard shortcut used to start and stop dictation.",
                    validate: validate,
                    onShortcutRecorded: record,
                    onRecordingStateReset: clearMessage,
                    onValidationError: showValidationMessage
                )
                .frame(width: 150, height: SettingsScreenLayout.settingsControlSurfaceHeight)
                .disabled(!supportsVoiceInput)

                Button("Reset", action: reset)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!supportsVoiceInput || shortcut == preferredShortcut)
                    .help("Restores the preferred voice-input shortcut.")
                    .accessibilityLabel("Reset voice input shortcut")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            if let visibleMessage {
                Text(visibleMessage.text)
                    .font(.caption)
                    .foregroundStyle(visibleMessage.style)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
                    .transition(.opacity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appSettingsChanged)) { _ in
            revalidate()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            revalidate()
        }
    }

    private var preferredShortcut: PhysicalKeyboardShortcut? {
        AppSettings.migratedVoiceInputShortcut(appShotShortcut: appShotShortcut)
    }

    private var visibleMessage: KeyboardShortcutRecorderMessage? {
        _ = validationRevision
        if let message {
            return message
        }
        guard supportsVoiceInput else {
            return .warning(VoiceInputShortcutUnavailableReason.unsupportedArchitecture.message)
        }
        guard let shortcut else {
            return .warning(VoiceInputShortcutUnavailableReason.notConfigured.message)
        }
        guard let validationMessage = validate(shortcut) else {
            return nil
        }
        return .warning(VoiceInputShortcutUnavailableReason.conflict(validationMessage).message)
    }

    private func validate(_ descriptor: PhysicalKeyboardShortcut) -> String? {
        PhysicalKeyboardShortcutValidation.message(
            for: descriptor,
            assignment: .voiceInput,
            appShotShortcut: appShotShortcut.keyChord,
            voiceInputShortcut: nil
        )
    }

    private func record(_ descriptor: PhysicalKeyboardShortcut) {
        shortcut = descriptor
        message = nil
    }

    private func reset() {
        shortcut = preferredShortcut
        message = shortcut == nil
            ? .warning("No conflict-free default is available. Record a shortcut to enable keyboard dictation.")
            : nil
    }

    private func showValidationMessage(_ text: String) {
        message = .warning(text)
    }

    private func clearMessage() {
        message = nil
    }

    private func revalidate() {
        validationRevision = UUID()
        message = nil
    }
}

enum VoiceInputSettingsHelp {
    static let shortcut = "Press or hold this app-local shortcut to mirror the microphone button. "
        + "Alveary rejects known macOS, app, composer, and App Shot conflicts."
}
