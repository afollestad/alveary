@preconcurrency import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import SwiftUI

struct AppShotsSettingsTabView: View {
    @Binding var appShotsEnabled: Bool
    @Binding var appShotShortcut: AppShotKeyboardShortcut
    let accessibilityAllowed: Bool
    let keyboardMonitoringAllowed: Bool
    let screenRecordingAllowed: Bool

    init(
        appShotsEnabled: Binding<Bool>,
        appShotShortcut: Binding<AppShotKeyboardShortcut>,
        accessibilityAllowed: Bool = AXIsProcessTrusted(),
        keyboardMonitoringAllowed: Bool = CGPreflightListenEventAccess(),
        screenRecordingAllowed: Bool = CGPreflightScreenCaptureAccess()
    ) {
        _appShotsEnabled = appShotsEnabled
        _appShotShortcut = appShotShortcut
        self.accessibilityAllowed = accessibilityAllowed
        self.keyboardMonitoringAllowed = keyboardMonitoringAllowed
        self.screenRecordingAllowed = screenRecordingAllowed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
            SettingsFormSection("Capture") {
                SettingsToggleRow(
                    "Enable app shots",
                    helpText: AppShotsSettingsHelp.enabled,
                    isOn: $appShotsEnabled
                )

                SettingsFormRow(showsDivider: false) {
                    SettingsResponsiveControlRow(
                        "Shortcut",
                        helpText: AppShotsSettingsHelp.shortcut,
                        horizontalControlSizing: .fillsAvailableWidthFraction(0.62)
                    ) {
                        AppShotShortcutRecorder(
                            shortcut: $appShotShortcut
                        )
                    }
                }
            }

            SettingsFormSection("Status") {
                AppShotStatusRow(
                    title: "Accessibility",
                    value: accessibilityAllowed ? "Allowed" : "Needs permission"
                )

                AppShotStatusRow(
                    title: "Keyboard Monitoring",
                    value: keyboardMonitoringAllowed ? "Allowed" : "Needed for ⌘⌘"
                )

                AppShotStatusRow(
                    title: "Screen Recording",
                    value: screenRecordingAllowed ? "Allowed" : "Needs permission",
                    showsDivider: false
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AppShotStatusRow: View {
    let title: String
    let value: String
    var showsDivider = true

    var body: some View {
        SettingsFormRow(showsDivider: showsDivider) {
            SettingsResponsiveControlRow(title, horizontalControlSizing: .intrinsicInline) {
                Text(value)
                    .foregroundStyle(value == "Allowed" ? Color.secondary : Color.orange)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

private struct AppShotShortcutRecorder: View {
    @Binding var shortcut: AppShotKeyboardShortcut

    @State private var isRecording = false
    @State private var keyMonitor: Any?
    @State private var message: AppShotShortcutRecorderMessage?

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                Text(shortcut.displayString)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(minWidth: 72, alignment: .center)
                    .padding(.horizontal, 10)
                    .frame(height: SettingsScreenLayout.settingsControlSurfaceHeight)
                    .background(
                        RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
                            .fill(Color.secondary.opacity(0.14))
                    )
                    .accessibilityHidden(true)

                Button(action: startRecording) {
                    Label(isRecording ? "Press keys" : "Record", systemImage: isRecording ? "keyboard.badge.ellipsis" : "record.circle")
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(isRecording ? "Recording app shot shortcut" : "Record app shot shortcut")

                Button("Use ⌘⌘") {
                    stopRecording()
                    shortcut = .bothCommand
                    message = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(shortcut == .bothCommand)
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
        .onDisappear(perform: stopRecording)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("App shot shortcut")
        .accessibilityValue(shortcut.displayString)
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        message = .info("Press a shortcut. Esc cancels.")
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event)
            return nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            message = nil
            return
        }

        guard let recordedShortcut = AppShotKeyboardShortcut.recorded(from: event) else {
            message = .warning("Use Command, Control, or Option with the key.")
            return
        }
        if let validationMessage = AppShotKeyboardShortcut.validationMessage(
            for: recordedShortcut,
            currentShortcut: shortcut
        ) {
            message = .warning(validationMessage)
            return
        }

        shortcut = recordedShortcut
        stopRecording()
        message = nil
    }

    private func stopRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        isRecording = false
    }
}

private struct AppShotShortcutRecorderMessage: Equatable {
    let text: String
    let style: Color

    static func info(_ text: String) -> AppShotShortcutRecorderMessage {
        AppShotShortcutRecorderMessage(text: text, style: .secondary)
    }

    static func warning(_ text: String) -> AppShotShortcutRecorderMessage {
        AppShotShortcutRecorderMessage(text: text, style: .orange)
    }
}

private enum AppShotsSettingsHelp {
    static let enabled = "When enabled, Alveary can capture the last focused non-Alveary window and stage it in the selected conversation."
    static let shortcut = "Record a regular key chord for system hot-key registration, or use the modifier-only shortcut. " +
        "Alveary rejects known conflicting shortcuts when macOS exposes the conflict."
}
