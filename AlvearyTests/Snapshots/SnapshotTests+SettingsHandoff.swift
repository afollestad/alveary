import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testSettingsScreenHandoffTab() {
        var settings = AppSettings()
        settings.contextManagementEnabled = true

        assertMacSnapshot(
            handoffSettingsScreen(settings: settings),
            size: CGSize(width: 1100, height: 820),
            named: "settings_screen_handoff"
        )
    }

    func testSettingsScreenHandoffTabSteeringDisabled() {
        var settings = AppSettings()
        settings.contextManagementEnabled = true
        settings.handoffSteeringEnabled = false

        assertMacSnapshot(
            handoffSettingsScreen(settings: settings),
            size: CGSize(width: 1100, height: 820),
            named: "settings_screen_handoff_steering_disabled"
        )
    }

    func testSettingsScreenHandoffTabNarrowKeepsControlsInline() {
        var settings = AppSettings()
        settings.contextManagementEnabled = true

        assertMacSnapshot(
            handoffSettingsScreen(settings: settings),
            size: CGSize(width: 400, height: 900),
            named: "settings_screen_handoff_narrow_controls"
        )
    }
}

private extension SnapshotTests {
    // The Handoff tab reads no provider state, so it needs no provider-discovery stub.
    func handoffSettingsScreen(settings: AppSettings) -> some View {
        SettingsScreen(
            viewModel: SettingsViewModel(settingsService: InMemorySettingsService(current: settings)),
            gitHubCLI: SidebarMockGitHubCLIService(installedVersion: nil, authenticated: false),
            appUpdateManager: snapshotAppUpdateManager(),
            onClose: {},
            initialTabRawValue: "handoff"
        )
    }
}
