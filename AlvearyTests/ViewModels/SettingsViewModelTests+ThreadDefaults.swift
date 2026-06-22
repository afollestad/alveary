import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension SettingsViewModelTests {
    func testThreadDefaultProvidersOnlyIncludeInstalledSetupReadyProviders() async {
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(),
            providerDiscovery: RecordingProviderDiscoveryService(statuses: [
                .claude: Self.providerStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions),
                .codex: Self.providerStatus(
                    for: .codex,
                    setup: .needsSetup,
                    modelOptions: AgentModelOptionTestFixtures.codexModelOptions
                )
            ])
        )

        await viewModel.refreshProviderStatuses()

        XCTAssertEqual(viewModel.threadDefaultProviderIDs, ["claude"])
        XCTAssertEqual(viewModel.threadDefaultProviderSelection, "claude")
    }

    func testThreadDefaultProvidersExcludeDisabledProvidersEvenWhenStatusIsReady() async {
        var settings = AppSettings()
        settings.disabledProviderIDs = ["claude"]
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(current: settings),
            providerDiscovery: RecordingProviderDiscoveryService(statuses: [
                .claude: Self.providerStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions),
                .codex: Self.providerStatus(for: .codex, modelOptions: AgentModelOptionTestFixtures.codexModelOptions)
            ])
        )

        await viewModel.refreshProviderStatuses()

        XCTAssertEqual(viewModel.threadDefaultProviderIDs, ["codex"])
        XCTAssertEqual(viewModel.threadDefaultProviderSelection, "codex")
    }

    func testThreadDefaultProvidersExcludeProviderStatusDisabledProviders() async {
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(),
            providerDiscovery: RecordingProviderDiscoveryService(statuses: [
                .claude: Self.providerStatus(
                    for: .claude,
                    isEnabled: false,
                    modelOptions: AgentModelOptionTestFixtures.claudeModelOptions
                ),
                .codex: Self.providerStatus(for: .codex, modelOptions: AgentModelOptionTestFixtures.codexModelOptions)
            ])
        )

        await viewModel.refreshProviderStatuses()

        XCTAssertEqual(viewModel.threadDefaultProviderIDs, ["codex"])
        XCTAssertEqual(viewModel.threadDefaultProviderSelection, "codex")
    }

    func testThreadDefaultRefreshPersistsFallbackWhenStoredProviderIsMissing() async {
        var settings = AppSettings()
        settings.defaultProvider = "codex"
        settings.defaultModel = "gpt-5.4-mini"
        settings.permissionMode = "never"
        let service = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(
            settingsService: service,
            providerDiscovery: RecordingProviderDiscoveryService(statuses: [
                .claude: Self.providerStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions),
                .codex: Self.providerStatus(
                    for: .codex,
                    installation: .missing,
                    modelOptions: AgentModelOptionTestFixtures.codexModelOptions
                )
            ])
        )

        await viewModel.refreshProviderStatuses()

        XCTAssertEqual(viewModel.threadDefaultProviderIDs, ["claude"])
        XCTAssertEqual(service.current.defaultProvider, "claude")
        XCTAssertEqual(service.current.defaultModel, AppSettings.defaultModelValue)
        XCTAssertEqual(service.current.permissionMode, "default")
    }

    func testThreadDefaultRefreshCoercesStaleModelForReadyProvider() async {
        var settings = AppSettings()
        settings.defaultProvider = "claude"
        settings.defaultModel = "not-a-real-model"
        let service = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(
            settingsService: service,
            providerDiscovery: RecordingProviderDiscoveryService(statuses: [
                .claude: Self.providerStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions)
            ])
        )

        await viewModel.refreshProviderStatuses()

        XCTAssertEqual(service.current.defaultProvider, "claude")
        XCTAssertEqual(service.current.defaultModel, AppSettings.defaultModelValue)
        XCTAssertEqual(viewModel.threadDefaultModelSelection, "sonnet")
    }

    func testThreadDefaultProvidersEmptyWhenNoProviderIsReady() async {
        let service = InMemorySettingsService()
        let viewModel = SettingsViewModel(
            settingsService: service,
            providerDiscovery: RecordingProviderDiscoveryService(statuses: [
                .claude: Self.providerStatus(
                    for: .claude,
                    installation: .missing,
                    modelOptions: AgentModelOptionTestFixtures.claudeModelOptions
                ),
                .codex: Self.providerStatus(
                    for: .codex,
                    setup: .needsSetup,
                    modelOptions: AgentModelOptionTestFixtures.codexModelOptions
                )
            ])
        )

        await viewModel.refreshProviderStatuses()

        XCTAssertFalse(viewModel.isCheckingThreadDefaultProviders)
        XCTAssertFalse(viewModel.hasReadyThreadDefaultProvider)
        XCTAssertTrue(viewModel.threadDefaultProviderIDs.isEmpty)
        XCTAssertEqual(service.current.defaultProvider, "claude")
    }
}
