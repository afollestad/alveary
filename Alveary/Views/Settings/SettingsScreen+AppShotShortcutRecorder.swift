import SwiftUI

struct AppShotShortcutRecorder: View {
    @Binding var shortcut: AppShotKeyboardShortcut
    let voiceInputShortcut: PhysicalKeyboardShortcut?

    @State private var message: KeyboardShortcutRecorderMessage?

    init(
        shortcut: Binding<AppShotKeyboardShortcut>,
        voiceInputShortcut: PhysicalKeyboardShortcut? = nil
    ) {
        _shortcut = shortcut
        self.voiceInputShortcut = voiceInputShortcut
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 10) {
                PhysicalKeyboardShortcutRecorderButton(
                    currentShortcut: shortcut.keyChord,
                    displayString: shortcut.displayString,
                    accessibilityLabel: "App shot keyboard shortcut",
                    accessibilityHelp: "Records the global keyboard shortcut used to capture an app shot.",
                    allowsModifierKey: true,
                    invalidShortcutMessage: "Use at least two modifier keys.",
                    recordedShortcutDisplay: { AppShotKeyboardShortcut(keyChord: $0).displayString },
                    validate: validate,
                    onShortcutRecorded: record,
                    onRecordingStateReset: clearMessage,
                    onValidationError: showValidationMessage
                )
                .frame(width: 150, height: SettingsScreenLayout.settingsControlSurfaceHeight)

                Button("Use Default", action: restoreDefault)
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

    private func validate(_ descriptor: PhysicalKeyboardShortcut) -> String? {
        AppShotKeyboardShortcut.validationMessage(
            for: AppShotKeyboardShortcut(keyChord: descriptor),
            currentShortcut: shortcut,
            voiceInputShortcut: voiceInputShortcut
        )
    }

    private func record(_ descriptor: PhysicalKeyboardShortcut) {
        shortcut = AppShotKeyboardShortcut(keyChord: descriptor)
        message = nil
    }

    private func restoreDefault() {
        if let validationMessage = AppShotKeyboardShortcut.validationMessage(
            for: AppSettings.defaultAppShotShortcut,
            currentShortcut: shortcut,
            voiceInputShortcut: voiceInputShortcut
        ) {
            showValidationMessage(validationMessage)
            return
        }
        shortcut = AppSettings.defaultAppShotShortcut
        message = nil
    }

    private func showValidationMessage(_ text: String) {
        message = .warning(text)
    }

    private func clearMessage() {
        message = nil
    }
}

typealias AppShotShortcutRecorderMessage = KeyboardShortcutRecorderMessage
