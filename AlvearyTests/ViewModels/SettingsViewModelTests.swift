import XCTest

@testable import Alveary

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testRefreshProviderStatusesLoadsDetectedStatusAndHelperMetadata() async {
        let detection = RecordingProviderDetectionService(statuses: [
            "claude": .connected(path: "/usr/local/bin/claude", version: "2.1.104")
        ])
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(),
            providerDetection: detection
        )

        await viewModel.refreshProviderStatuses()
        let checkAllProvidersInvocations = await detection.checkAllProvidersInvocations()

        XCTAssertEqual(viewModel.providerStatus(for: "claude"), .connected(path: "/usr/local/bin/claude", version: "2.1.104"))
        XCTAssertEqual(viewModel.shortStatusLabel(for: viewModel.providerStatus(for: "claude")), "Connected")
        XCTAssertEqual(viewModel.statusDescription(for: viewModel.providerStatus(for: "claude")), "2.1.104 at /usr/local/bin/claude")
        XCTAssertEqual(viewModel.installCommand(for: "claude"), "curl -fsSL https://claude.ai/install.sh | bash")
        XCTAssertEqual(checkAllProvidersInvocations, 1)
    }

    func testRefreshProviderStatusesIfNeededOnlyLoadsOnce() async {
        let detection = RecordingProviderDetectionService(statuses: [
            "claude": .missing
        ])
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(),
            providerDetection: detection
        )

        await viewModel.refreshProviderStatusesIfNeeded()
        await viewModel.refreshProviderStatusesIfNeeded()
        let checkAllProvidersInvocations = await detection.checkAllProvidersInvocations()

        XCTAssertEqual(viewModel.providerStatus(for: "claude"), .missing)
        XCTAssertEqual(checkAllProvidersInvocations, 1)
    }

    func testOptionSourcesAreStableAndPickerSafe() {
        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService())

        XCTAssertEqual(viewModel.availableProviderIDs, ["claude"])
        XCTAssertEqual(viewModel.permissionModeOptions(for: "claude"), AppSettings.supportedPermissionModes)
        XCTAssertEqual(viewModel.effortOptions(for: "claude"), AppSettings.supportedEffortLevels)
        XCTAssertEqual(viewModel.themeOptions, ["system", "light", "dark"])
        XCTAssertEqual(viewModel.availableSoundNames, ["Glass", "Pop", "Tink", "Purr"])
        XCTAssertTrue(viewModel.permissionModeOptions(for: "unknown").isEmpty)
        XCTAssertTrue(viewModel.effortOptions(for: "unknown").isEmpty)
    }

    func testGettersReflectCurrentSettings() {
        let service = InMemorySettingsService()
        service.update {
            $0.permissionMode = "plan"
            $0.effort = "high"
            $0.deleteKeyAction = .delete
            $0.autoGenerateNames = false
            $0.reopenLastThreadAndConversationOnLaunch = true
            $0.autoTrustWorktrees = false
            $0.createWorktreeByDefault = true
            $0.theme = "dark"
            $0.codeFontFamily = "Monaco"
            $0.codeFontSize = 15
            $0.chatFontSize = 18
            $0.notifications.enabled = false
            $0.notifications.osNotifications = false
            $0.notifications.sound = false
            $0.notifications.soundName = "Tink"
            $0.branchPrefix = "feature"
            $0.pushOnCreate = true
            $0.providerConfigs["claude"] = ProviderCustomConfig(cli: "/usr/local/bin/claude")
        }
        let viewModel = SettingsViewModel(settingsService: service)

        XCTAssertEqual(viewModel.defaultProvider, "claude")
        XCTAssertEqual(viewModel.permissionMode, "plan")
        XCTAssertEqual(viewModel.effort, "high")
        XCTAssertEqual(viewModel.deleteKeyAction, .delete)
        XCTAssertFalse(viewModel.autoGenerateNames)
        XCTAssertTrue(viewModel.reopenLastThreadAndConversationOnLaunch)
        XCTAssertFalse(viewModel.autoTrustWorktrees)
        XCTAssertTrue(viewModel.createWorktreeByDefault)
        XCTAssertEqual(viewModel.theme, "dark")
        XCTAssertEqual(viewModel.codeFontFamily, "Monaco")
        XCTAssertEqual(viewModel.codeFontSize, 15)
        XCTAssertEqual(viewModel.chatFontSize, 18)
        XCTAssertFalse(viewModel.notificationsEnabled)
        XCTAssertFalse(viewModel.osNotificationsEnabled)
        XCTAssertFalse(viewModel.soundEnabled)
        XCTAssertEqual(viewModel.soundName, "Tink")
        XCTAssertEqual(viewModel.branchPrefix, "feature")
        XCTAssertTrue(viewModel.pushOnCreate)
        XCTAssertEqual(viewModel.providerConfig(for: "claude").cli, "/usr/local/bin/claude")
    }

    func testSettersWriteBackToSettingsService() {
        let service = InMemorySettingsService()
        let viewModel = SettingsViewModel(settingsService: service)

        viewModel.defaultProvider = "claude"
        viewModel.permissionMode = "bypassPermissions"
        viewModel.effort = "max"
        viewModel.deleteKeyAction = .delete
        viewModel.autoGenerateNames = false
        viewModel.reopenLastThreadAndConversationOnLaunch = true
        viewModel.autoTrustWorktrees = false
        viewModel.createWorktreeByDefault = true
        viewModel.theme = "light"
        viewModel.codeFontFamily = "Monaco"
        viewModel.codeFontSize = 16
        viewModel.chatFontSize = 17
        viewModel.notificationsEnabled = false
        viewModel.osNotificationsEnabled = false
        viewModel.soundEnabled = false
        viewModel.soundName = "Pop"
        viewModel.branchPrefix = "feature"
        viewModel.pushOnCreate = true

        XCTAssertEqual(service.current.defaultProvider, "claude")
        XCTAssertEqual(service.current.permissionMode, "bypassPermissions")
        XCTAssertEqual(service.current.effort, "max")
        XCTAssertEqual(service.current.deleteKeyAction, .delete)
        XCTAssertFalse(service.current.autoGenerateNames)
        XCTAssertTrue(service.current.reopenLastThreadAndConversationOnLaunch)
        XCTAssertFalse(service.current.autoTrustWorktrees)
        XCTAssertTrue(service.current.createWorktreeByDefault)
        XCTAssertEqual(service.current.theme, "light")
        XCTAssertEqual(service.current.codeFontFamily, "Monaco")
        XCTAssertEqual(service.current.codeFontSize, 16)
        XCTAssertEqual(service.current.chatFontSize, 17)
        XCTAssertFalse(service.current.notifications.enabled)
        XCTAssertFalse(service.current.notifications.osNotifications)
        XCTAssertFalse(service.current.notifications.sound)
        XCTAssertEqual(service.current.notifications.soundName, "Pop")
        XCTAssertEqual(service.current.branchPrefix, "feature")
        XCTAssertTrue(service.current.pushOnCreate)
    }

    func testProviderConfigHelpersCreateEntriesAndPreserveOtherProviders() {
        let service = InMemorySettingsService()
        service.update {
            $0.providerConfigs["other"] = ProviderCustomConfig(cli: "/usr/bin/other")
        }
        let viewModel = SettingsViewModel(settingsService: service)

        XCTAssertEqual(viewModel.providerConfig(for: "claude"), ProviderCustomConfig())

        viewModel.updateProviderConfig(for: "claude") {
            $0.cli = "/usr/local/bin/claude"
            $0.extraArgs = "--verbose"
        }

        XCTAssertEqual(service.current.providerConfigs["claude"], ProviderCustomConfig(cli: "/usr/local/bin/claude", extraArgs: "--verbose"))
        XCTAssertEqual(service.current.providerConfigs["other"], ProviderCustomConfig(cli: "/usr/bin/other"))
    }

    func testSoundNameFallsBackToGlassWhenStoredValueIsNil() {
        let service = InMemorySettingsService()
        service.update { $0.notifications.soundName = nil }
        let viewModel = SettingsViewModel(settingsService: service)

        XCTAssertEqual(viewModel.soundName, "Glass")
    }
}

private actor RecordingProviderDetectionService: ProviderDetectionService {
    private let statuses: [String: ProviderStatus]
    private var checkAllProvidersCallCount = 0

    init(statuses: [String: ProviderStatus]) {
        self.statuses = statuses
    }

    func resolvedPath(for providerId: String) -> String? {
        if case let .connected(path, _)? = statuses[providerId] {
            return path
        }
        return nil
    }

    func status(for providerId: String) -> ProviderStatus {
        statuses[providerId] ?? .missing
    }

    func checkAllProviders() async {
        checkAllProvidersCallCount += 1
    }

    func checkProvider(_ providerId: String) async {}

    func checkAllProvidersInvocations() -> Int {
        checkAllProvidersCallCount
    }
}
