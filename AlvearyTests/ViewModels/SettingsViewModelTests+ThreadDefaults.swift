import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension SettingsViewModelTests {
    func testThreadDefaultHarnessesOnlyIncludeInstalledSetupReadyHarnesses() async {
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(),
            harnessDiscovery: RecordingHarnessDiscoveryService(statuses: [
                .claude: Self.harnessStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions),
                .codex: Self.harnessStatus(
                    for: .codex,
                    setup: .needsSetup,
                    modelOptions: AgentModelOptionTestFixtures.codexModelOptions
                )
            ])
        )

        await viewModel.refreshHarnessStatuses()

        XCTAssertEqual(viewModel.threadDefaultHarnessIDs, ["claude"])
        XCTAssertEqual(viewModel.threadDefaultHarnessSelection, "claude")
    }

    func testThreadDefaultHarnessesExcludeDisabledHarnessesEvenWhenStatusIsReady() async {
        var settings = AppSettings()
        settings.disabledHarnessIDs = ["claude"]
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(current: settings),
            harnessDiscovery: RecordingHarnessDiscoveryService(statuses: [
                .claude: Self.harnessStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions),
                .codex: Self.harnessStatus(for: .codex, modelOptions: AgentModelOptionTestFixtures.codexModelOptions)
            ])
        )

        await viewModel.refreshHarnessStatuses()

        XCTAssertEqual(viewModel.threadDefaultHarnessIDs, ["codex"])
        XCTAssertEqual(viewModel.threadDefaultHarnessSelection, "codex")
    }

    func testThreadDefaultHarnessesExcludeHarnessStatusDisabledHarnesses() async {
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(),
            harnessDiscovery: RecordingHarnessDiscoveryService(statuses: [
                .claude: Self.harnessStatus(
                    for: .claude,
                    isEnabled: false,
                    modelOptions: AgentModelOptionTestFixtures.claudeModelOptions
                ),
                .codex: Self.harnessStatus(for: .codex, modelOptions: AgentModelOptionTestFixtures.codexModelOptions)
            ])
        )

        await viewModel.refreshHarnessStatuses()

        XCTAssertEqual(viewModel.threadDefaultHarnessIDs, ["codex"])
        XCTAssertEqual(viewModel.threadDefaultHarnessSelection, "codex")
    }

    func testThreadDefaultRefreshPersistsFallbackWhenStoredHarnessIsMissing() async {
        var settings = AppSettings()
        settings.defaultHarness = "codex"
        settings.defaultModel = "gpt-5.4-mini"
        settings.permissionMode = "never"
        let service = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(
            settingsService: service,
            harnessDiscovery: RecordingHarnessDiscoveryService(statuses: [
                .claude: Self.harnessStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions),
                .codex: Self.harnessStatus(
                    for: .codex,
                    installation: .missing,
                    modelOptions: AgentModelOptionTestFixtures.codexModelOptions
                )
            ])
        )

        await viewModel.refreshHarnessStatuses()

        XCTAssertEqual(viewModel.threadDefaultHarnessIDs, ["claude"])
        XCTAssertEqual(service.current.defaultHarness, "claude")
        XCTAssertEqual(service.current.defaultModel, AppSettings.defaultModelValue)
        XCTAssertEqual(service.current.permissionMode, "default")
    }

    func testThreadDefaultRefreshCoercesStaleModelForReadyHarness() async {
        var settings = AppSettings()
        settings.defaultHarness = "claude"
        settings.defaultModel = "not-a-real-model"
        let service = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(
            settingsService: service,
            harnessDiscovery: RecordingHarnessDiscoveryService(statuses: [
                .claude: Self.harnessStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions)
            ])
        )

        await viewModel.refreshHarnessStatuses()

        XCTAssertEqual(service.current.defaultHarness, "claude")
        XCTAssertEqual(service.current.defaultModel, AppSettings.defaultModelValue)
        XCTAssertEqual(viewModel.threadDefaultModelSelection, "sonnet")
    }

    func testThreadDefaultHarnessesEmptyWhenNoHarnessIsReady() async {
        let service = InMemorySettingsService()
        let viewModel = SettingsViewModel(
            settingsService: service,
            harnessDiscovery: RecordingHarnessDiscoveryService(statuses: [
                .claude: Self.harnessStatus(
                    for: .claude,
                    installation: .missing,
                    modelOptions: AgentModelOptionTestFixtures.claudeModelOptions
                ),
                .codex: Self.harnessStatus(
                    for: .codex,
                    setup: .needsSetup,
                    modelOptions: AgentModelOptionTestFixtures.codexModelOptions
                )
            ])
        )

        await viewModel.refreshHarnessStatuses()

        XCTAssertFalse(viewModel.isCheckingThreadDefaultHarnesses)
        XCTAssertFalse(viewModel.hasReadyThreadDefaultHarness)
        XCTAssertTrue(viewModel.threadDefaultHarnessIDs.isEmpty)
        XCTAssertEqual(service.current.defaultHarness, "claude")
    }
}
