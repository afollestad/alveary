import AppKit
import SwiftUI

struct MenuBarSettingsTabView: View {
    private static let loginItemsSettingsURLCandidates = [
        "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
        "x-apple.systempreferences:com.apple.preferences.users"
    ]

    let viewModel: SettingsViewModel
    @Binding var showsMenuBarIcon: Bool
    @Binding var showsPullRequestsNeedingReview: Bool
    @Binding var pullRequestRefreshInterval: MenuBarPullRequestRefreshInterval

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

            SettingsFormSection("Pull requests") {
                SettingsToggleRow(
                    "Show PRs needing review",
                    helpText: pullRequestsHelpText,
                    isOn: $showsPullRequestsNeedingReview,
                    isDisabled: !canListPullRequests
                )

                SettingsFormRow(showsDivider: false) {
                    SettingsResponsiveControlRow(
                        "Refresh every",
                        helpText: "How often Alveary checks GitHub in the background.",
                        horizontalControlSizing: .intrinsic
                    ) {
                        SettingsMenuPicker(
                            "Refresh every",
                            selection: $pullRequestRefreshInterval,
                            options: MenuBarPullRequestRefreshInterval.allCases,
                            isDisabled: !canListPullRequests || !showsPullRequestsNeedingReview,
                            label: \.label
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

    /// The list needs both the icon to hang from and the pull-request integration, which the
    /// Git tab can switch off; `MenuBarController.listsPullRequestsNeedingReview` reads the same three.
    private var canListPullRequests: Bool {
        showsMenuBarIcon && viewModel.pullRequestsEnabled
    }

    private var pullRequestsHelpText: String {
        guard viewModel.pullRequestsEnabled else {
            return "Turn on pull requests in Git settings to list the ones waiting on your review here."
        }
        return "Lists open pull requests waiting on your review, except ignored ones, and adds a dot to the menu bar icon while any are waiting."
    }

    private var launchAtStartupBinding: Binding<Bool> {
        Binding(
            get: { viewModel.launchAtStartup },
            set: { viewModel.setLaunchAtStartup($0) }
        )
    }
}
