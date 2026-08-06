import SwiftUI

struct AppShotShortcutRecorder: View {
    @Binding var shortcut: AppShotKeyboardShortcut
    let voiceInputShortcut: PhysicalKeyboardShortcut?
    let inputMonitoringAllowed: Bool

    @State private var message: KeyboardShortcutRecorderMessage?

    init(
        shortcut: Binding<AppShotKeyboardShortcut>,
        voiceInputShortcut: PhysicalKeyboardShortcut? = nil,
        inputMonitoringAllowed: Bool = true
    ) {
        _shortcut = shortcut
        self.voiceInputShortcut = voiceInputShortcut
        self.inputMonitoringAllowed = inputMonitoringAllowed
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

            // Derived rather than routed through `message`, which `record` clears the instant a
            // shortcut is chosen — exactly when this warning needs to appear.
            if showsInputMonitoringWarning {
                Text("⌘⌘ only works while Alveary is focused until Input Monitoring is granted below.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("App shot shortcut")
        .accessibilityValue(shortcut.displayString)
    }

    /// Only modifier-only shortcuts need an event tap; regular chords use a Carbon hot key.
    private var showsInputMonitoringWarning: Bool {
        shortcut == .bothCommand && !inputMonitoringAllowed
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
