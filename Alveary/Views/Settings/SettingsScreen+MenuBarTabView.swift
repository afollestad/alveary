import AppKit
import SwiftUI

struct MenuBarSettingsTabView: View {
    private static let loginItemsSettingsURLCandidates = [
        "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
        "x-apple.systempreferences:com.apple.preferences.users"
    ]

    let viewModel: SettingsViewModel
    @Binding var showsMenuBarIcon: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
            SettingsFormSection {
                SettingsToggleRow(
                    "Show menu bar icon",
                    helpText: "Adds an Alveary icon to the system menu bar for recent threads and quick actions.",
                    isOn: $showsMenuBarIcon
                )

                SettingsToggleRow(
                    "Launch at startup",
                    helpText: "Opens Alveary automatically after you log in to macOS.",
                    isOn: launchAtStartupBinding,
                    showsDivider: viewModel.launchAtStartupHint != nil
                )

                if let hint = viewModel.launchAtStartupHint {
                    SettingsFormRow(showsDivider: false) {
                        SettingsSystemSettingsHintRow(
                            message: hint,
                            urlCandidates: Self.loginItemsSettingsURLCandidates
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The view model outlives this tab, and the registration is read once when it is built.
        .task {
            viewModel.refreshLaunchAtStartupStatus()
        }
        // The hint's button sends the user to System Settings, and the login item can be switched
        // off there without Alveary running at all; re-read whenever the app comes back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshLaunchAtStartupStatus()
        }
    }

    private var launchAtStartupBinding: Binding<Bool> {
        Binding(
            get: { viewModel.launchAtStartup },
            set: { viewModel.setLaunchAtStartup($0) }
        )
    }
}
