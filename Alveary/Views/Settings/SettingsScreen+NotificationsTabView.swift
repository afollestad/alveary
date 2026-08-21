import AppKit
import SwiftUI

struct NotificationsSettingsTabView: View {
    private static let notificationSettingsURLCandidates = [
        "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
        "x-apple.systempreferences:com.apple.preference.notifications"
    ]

    let viewModel: SettingsViewModel
    @Binding var notificationsEnabled: Bool
    @Binding var osNotificationsEnabled: Bool
    @Binding var soundEnabled: Bool
    @Binding var soundName: String

    @State private var isDeniedBySystem: Bool

    private let refreshesLiveAuthorization: Bool

    init(
        viewModel: SettingsViewModel,
        notificationsEnabled: Binding<Bool>,
        osNotificationsEnabled: Binding<Bool>,
        soundEnabled: Binding<Bool>,
        soundName: Binding<String>,
        systemDeniedOverride: Bool? = nil
    ) {
        self.viewModel = viewModel
        _notificationsEnabled = notificationsEnabled
        _osNotificationsEnabled = osNotificationsEnabled
        _soundEnabled = soundEnabled
        _soundName = soundName
        // Snapshots inject the state; production reads it live, following the App Shots tab.
        _isDeniedBySystem = State(initialValue: systemDeniedOverride ?? false)
        // Suppressed under app-hosted tests too: two `SnapshotTests` cases render this tab with no
        // override, and reading the real status would both touch the OS and let the developer's
        // own grant decide whether the denial hint lands in their baselines.
        refreshesLiveAuthorization = systemDeniedOverride == nil && !UserNotificationGateway.isSuppressed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
            SettingsFormSection {
                SettingsToggleRow("Enable notifications", isOn: $notificationsEnabled)

                SettingsToggleRow(
                    "Use macOS notifications",
                    isOn: $osNotificationsEnabled,
                    isDisabled: !viewModel.notificationsEnabled
                )

                if showsSystemDenialHint {
                    SettingsFormRow {
                        systemDenialHint
                    }
                }

                SettingsToggleRow(
                    "Play sounds",
                    isOn: $soundEnabled,
                    isDisabled: !viewModel.notificationsEnabled
                )

                SettingsFormRow(showsDivider: false) {
                    SettingsResponsiveControlRow("Sound", horizontalControlSizing: .intrinsic) {
                        SettingsMenuPicker(
                            "Sound",
                            selection: $soundName,
                            options: viewModel.availableSoundNames,
                            label: { $0 }
                        )
                        .disabled(!viewModel.notificationsEnabled || !viewModel.soundEnabled)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await refreshSystemAuthorization()
        }
        // The remedy button sends the user to System Settings; re-check when they come back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshSystemAuthorization() }
        }
    }

    /// macOS silently drops every notification once denied, and the toggles above stay on, so the
    /// only honest signal is reading the system status back.
    private func refreshSystemAuthorization() async {
        guard refreshesLiveAuthorization else {
            return
        }
        let status = await UserNotificationGateway.authorizationStatus()
        isDeniedBySystem = status == .denied
    }

    private var showsSystemDenialHint: Bool {
        viewModel.notificationsEnabled && osNotificationsEnabled && isDeniedBySystem
    }

    private var systemDenialHint: some View {
        SettingsSystemSettingsHintRow(
            message: "macOS is blocking notifications from Alveary, so none will be delivered.",
            urlCandidates: Self.notificationSettingsURLCandidates
        )
    }
}
