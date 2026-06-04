import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testRefreshProviderStatusesLoadsDetectedStatusAndHelperMetadata() async {
        let discovery = RecordingProviderDiscoveryService(statuses: [
            .claude: AgentCLIKit.AgentProviderStatus(
                providerId: .claude,
                definition: AgentCLIKit.ClaudeProviderDefinition.definition,
                installation: .installed,
                availability: AgentCLIKit.AgentProviderAvailability(
                    providerId: .claude,
                    executablePath: "/usr/local/bin/claude",
                    versionDescription: "2.1.104"
                ),
                setup: .ready,
                modelOptions: AgentModelOptionTestFixtures.claudeModelOptions
            )
        ])
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(),
            providerDiscovery: discovery
        )

        await viewModel.refreshProviderStatuses()
        let providerStatusesInvocations = await discovery.providerStatusesInvocations()

        XCTAssertEqual(viewModel.providerStatus(for: "claude")?.installation, .installed)
        XCTAssertEqual(viewModel.shortStatusLabel(for: viewModel.providerStatus(for: "claude")), "Ready")
        XCTAssertEqual(viewModel.statusDescription(for: viewModel.providerStatus(for: "claude")), "2.1.104 at /usr/local/bin/claude")
        XCTAssertEqual(viewModel.installCommand(for: "claude"), "curl -fsSL https://claude.ai/install.sh | bash")
        XCTAssertEqual(providerStatusesInvocations, 1)
    }

    func testRefreshProviderStatusesIfNeededOnlyLoadsOnce() async {
        let discovery = RecordingProviderDiscoveryService(statuses: [
            .claude: AgentCLIKit.AgentProviderStatus(
                providerId: .claude,
                definition: AgentCLIKit.ClaudeProviderDefinition.definition,
                installation: .missing,
                availability: AgentCLIKit.AgentProviderAvailability(providerId: .claude, executablePath: nil),
                setup: .ready,
                modelOptions: AgentModelOptionTestFixtures.claudeModelOptions
            )
        ])
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(),
            providerDiscovery: discovery
        )

        await viewModel.refreshProviderStatusesIfNeeded()
        await viewModel.refreshProviderStatusesIfNeeded()
        let providerStatusesInvocations = await discovery.providerStatusesInvocations()

        XCTAssertEqual(viewModel.providerStatus(for: "claude")?.installation, .missing)
        XCTAssertEqual(providerStatusesInvocations, 1)
    }

    func testOptionSourcesAreStableAndPickerSafe() async {
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(),
            providerDiscovery: RecordingProviderDiscoveryService(statuses: [
                .claude: Self.providerStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions),
                .codex: Self.providerStatus(for: .codex, modelOptions: AgentModelOptionTestFixtures.codexModelOptions)
            ])
        )

        await viewModel.refreshProviderStatuses()

        XCTAssertEqual(viewModel.availableProviderIDs, ["claude", "codex"])
        XCTAssertEqual(viewModel.supportedModels, ["default", "sonnet", "opus"])
        XCTAssertEqual(viewModel.permissionModeOptions(for: "claude"), AppSettings.supportedPermissionModes(forProvider: "claude"))
        XCTAssertEqual(viewModel.permissionModeOptions(for: "codex"), AppSettings.supportedPermissionModes(forProvider: "codex"))
        XCTAssertEqual(
            viewModel.effortOptions(for: "claude", model: "opus").map(\.value),
            ["low", "medium", "high", "xhigh", "max"]
        )
        XCTAssertEqual(
            viewModel.effortOptions(for: "claude", model: "sonnet").map(\.value),
            ["low", "medium", "high", "max"]
        )
        XCTAssertEqual(
            viewModel.effortOptions(for: "claude", model: "default").map(\.value),
            ["low", "medium", "high", "max"]
        )
        XCTAssertEqual(viewModel.themeOptions, ["system", "light", "dark"])
        XCTAssertEqual(viewModel.availableSoundNames, ["Glass", "Pop", "Tink", "Purr"])
        XCTAssertEqual(viewModel.codeFontFamilyOptions, [AppSettings.defaultCodeFontFamily])
        XCTAssertTrue(viewModel.permissionModeOptions(for: "unknown").isEmpty)
        XCTAssertTrue(viewModel.effortOptions(for: "unknown", model: "opus").isEmpty)
        XCTAssertEqual(viewModel.effortOptions(for: "codex", model: "gpt-5.5").map(\.value), ["low", "medium", "high", "xhigh"])
    }

    func testCodeFontFamilyOptionsLoadLazilyAndCacheResults() {
        var loadCount = 0
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(),
            codeFontFamilyLoader: {
                loadCount += 1
                return ["Monaco", "Monaco", "  "]
            }
        )

        XCTAssertEqual(viewModel.codeFontFamilyOptions, [AppSettings.defaultCodeFontFamily])
        XCTAssertEqual(loadCount, 0)

        viewModel.loadCodeFontFamilyOptionsIfNeeded()
        viewModel.loadCodeFontFamilyOptionsIfNeeded()

        XCTAssertEqual(viewModel.codeFontFamilyOptions, ["Monaco", "SF Mono"])
        XCTAssertEqual(loadCount, 1)
    }

    func testGettersReflectCurrentSettings() {
        let service = InMemorySettingsService()
        service.update {
            $0.defaultModel = "opus"
            $0.permissionMode = "plan"
            $0.effort = "high"
            $0.defaultThreadCleanupAction = .delete
            $0.defaultEnterBehavior = .steer
            $0.reopenLastThreadAndConversationOnLaunch = true
            $0.autoTrustProjects = false
            $0.createWorktreeByDefault = true
            $0.theme = "dark"
            $0.codeFontFamily = "Monaco"
            $0.codeFontSize = 15
            $0.chatFontSize = 18
            $0.expandTerminalWhenActionsRun = true
            $0.maxTerminalSessions = 12
            $0.notifications.enabled = false
            $0.notifications.osNotifications = false
            $0.notifications.sound = false
            $0.notifications.soundName = "Tink"
            $0.branchPrefix = "feature/"
            $0.providerConfigs["claude"] = ProviderCustomConfig(extraArgs: "--verbose")
        }
        let viewModel = SettingsViewModel(settingsService: service)

        XCTAssertEqual(viewModel.defaultProvider, "claude")
        XCTAssertEqual(viewModel.defaultModel, "opus")
        XCTAssertEqual(viewModel.permissionMode, "plan")
        XCTAssertEqual(viewModel.effort, "high")
        XCTAssertEqual(viewModel.defaultThreadCleanupAction, .delete)
        XCTAssertEqual(viewModel.defaultEnterBehavior, .steer)
        XCTAssertTrue(viewModel.reopenLastThreadAndConversationOnLaunch)
        XCTAssertFalse(viewModel.autoTrustProjects)
        XCTAssertTrue(viewModel.createWorktreeByDefault)
        XCTAssertEqual(viewModel.theme, "dark")
        XCTAssertEqual(viewModel.codeFontFamily, "Monaco")
        XCTAssertEqual(viewModel.codeFontSize, 15)
        XCTAssertEqual(viewModel.chatFontSize, 18)
        XCTAssertTrue(viewModel.expandTerminalWhenActionsRun)
        XCTAssertEqual(viewModel.maxTerminalSessions, 12)
        XCTAssertFalse(viewModel.notificationsEnabled)
        XCTAssertFalse(viewModel.osNotificationsEnabled)
        XCTAssertFalse(viewModel.soundEnabled)
        XCTAssertEqual(viewModel.soundName, "Tink")
        XCTAssertEqual(viewModel.branchPrefix, "feature/")
        XCTAssertEqual(viewModel.providerExtraArgs(for: "claude"), "--verbose")
    }

    func testContextManagementGettersReflectCurrentSettings() {
        let service = InMemorySettingsService()
        service.update {
            $0.contextManagementEnabled = false
            $0.sessionHandoffWindowPercentage = 75
            $0.handoffSteeringEnabled = false
            $0.handoffSteeringCountdownSeconds = 15
            $0.handoffPromptSendCountdownSeconds = 0
            $0.handoffContextCustomizationEnabled = false
            $0.sessionHandoffPrompt = "Custom handoff prompt"
        }
        let viewModel = SettingsViewModel(settingsService: service)

        XCTAssertFalse(viewModel.contextManagementEnabled)
        XCTAssertEqual(viewModel.sessionHandoffWindowPercentage, 75)
        XCTAssertFalse(viewModel.handoffSteeringEnabled)
        XCTAssertEqual(viewModel.handoffSteeringCountdownSeconds, 15)
        XCTAssertEqual(viewModel.handoffPromptSendCountdownSeconds, 0)
        XCTAssertFalse(viewModel.handoffContextCustomizationEnabled)
        XCTAssertEqual(viewModel.sessionHandoffPrompt, "Custom handoff prompt")
    }

    func testContextManagementSettersWriteBackToSettingsService() {
        let service = InMemorySettingsService()
        let viewModel = SettingsViewModel(settingsService: service)

        viewModel.contextManagementEnabled = false
        viewModel.sessionHandoffWindowPercentage = 80
        viewModel.handoffSteeringEnabled = false
        viewModel.handoffSteeringCountdownSeconds = 20
        viewModel.handoffPromptSendCountdownSeconds = 0
        viewModel.handoffContextCustomizationEnabled = false
        viewModel.sessionHandoffPrompt = "Updated handoff prompt"

        XCTAssertFalse(service.current.contextManagementEnabled)
        XCTAssertEqual(service.current.sessionHandoffWindowPercentage, 80)
        XCTAssertFalse(service.current.handoffSteeringEnabled)
        XCTAssertEqual(service.current.handoffSteeringCountdownSeconds, 20)
        XCTAssertEqual(service.current.handoffPromptSendCountdownSeconds, 0)
        XCTAssertFalse(service.current.handoffContextCustomizationEnabled)
        XCTAssertEqual(service.current.sessionHandoffPrompt, "Updated handoff prompt")
    }

    func testSettersWriteBackToSettingsService() {
        let service = InMemorySettingsService()
        let viewModel = SettingsViewModel(settingsService: service)

        viewModel.defaultProvider = "claude"
        viewModel.defaultModel = "sonnet"
        viewModel.permissionMode = "acceptEdits"
        viewModel.effort = "max"
        viewModel.defaultThreadCleanupAction = .delete
        viewModel.defaultEnterBehavior = .steer
        viewModel.reopenLastThreadAndConversationOnLaunch = true
        viewModel.autoTrustProjects = false
        viewModel.createWorktreeByDefault = true
        viewModel.theme = "light"
        viewModel.codeFontFamily = "Monaco"
        viewModel.codeFontSize = 16
        viewModel.chatFontSize = 17
        viewModel.expandTerminalWhenActionsRun = true
        viewModel.maxTerminalSessions = 12
        viewModel.notificationsEnabled = false
        viewModel.osNotificationsEnabled = false
        viewModel.soundEnabled = false
        viewModel.soundName = "Pop"
        viewModel.branchPrefix = "feature/"

        XCTAssertEqual(service.current.defaultProvider, "claude")
        XCTAssertEqual(service.current.defaultModel, "sonnet")
        XCTAssertEqual(service.current.permissionMode, "acceptEdits")
        XCTAssertEqual(service.current.effort, "max")
        XCTAssertEqual(service.current.defaultThreadCleanupAction, .delete)
        XCTAssertEqual(service.current.defaultEnterBehavior, .steer)
        XCTAssertTrue(service.current.reopenLastThreadAndConversationOnLaunch)
        XCTAssertFalse(service.current.autoTrustProjects)
        XCTAssertTrue(service.current.createWorktreeByDefault)
        XCTAssertEqual(service.current.theme, "light")
        XCTAssertEqual(service.current.codeFontFamily, "Monaco")
        XCTAssertEqual(service.current.codeFontSize, 16)
        XCTAssertEqual(service.current.chatFontSize, 17)
        XCTAssertTrue(service.current.expandTerminalWhenActionsRun)
        XCTAssertEqual(service.current.maxTerminalSessions, 12)
        XCTAssertFalse(service.current.notifications.enabled)
        XCTAssertFalse(service.current.notifications.osNotifications)
        XCTAssertFalse(service.current.notifications.sound)
        XCTAssertEqual(service.current.notifications.soundName, "Pop")
        XCTAssertEqual(service.current.branchPrefix, "feature/")
    }

    // Settings Effort picker must not silently retain a value the new model
    // rejects (e.g. `xhigh` when switching off Opus).
    func testDefaultModelSetterCoercesEffortWhenNewModelDoesNotSupportIt() async {
        let service = InMemorySettingsService()
        service.update {
            $0.defaultModel = "opus"
            $0.effort = "xhigh"
        }
        let viewModel = SettingsViewModel(
            settingsService: service,
            providerDiscovery: RecordingProviderDiscoveryService(statuses: [
                .claude: Self.providerStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions)
            ])
        )
        await viewModel.refreshProviderStatuses()

        viewModel.defaultModel = "sonnet"

        XCTAssertEqual(service.current.defaultModel, "sonnet")
        XCTAssertEqual(service.current.effort, AppSettings.defaultEffortLevel)
    }

    func testDefaultModelSetterPreservesEffortWhenNewModelStillSupportsIt() async {
        let service = InMemorySettingsService()
        service.update {
            $0.defaultModel = "sonnet"
            $0.effort = "high"
        }
        let viewModel = SettingsViewModel(
            settingsService: service,
            providerDiscovery: RecordingProviderDiscoveryService(statuses: [
                .claude: Self.providerStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions)
            ])
        )
        await viewModel.refreshProviderStatuses()

        viewModel.defaultModel = "opus"

        XCTAssertEqual(service.current.defaultModel, "opus")
        XCTAssertEqual(service.current.effort, "high")
    }

    func testDefaultModelGetterUsesOptionIDWhileSetterStoresProviderModelValue() async {
        let modelOption = AgentCLIKit.AgentModelOption(
            providerId: .codex,
            id: "codex-fast",
            model: "gpt-5.4-mini",
            label: "GPT-5.4-Mini",
            isDefault: true,
            supportedEffortOptions: AgentModelOptionTestFixtures.codexDefaultEfforts,
            defaultEffortOption: AgentModelOptionTestFixtures.medium
        )
        let service = InMemorySettingsService()
        service.update {
            $0.defaultProvider = "codex"
            $0.defaultModel = "gpt-5.4-mini"
        }
        let viewModel = SettingsViewModel(
            settingsService: service,
            providerDiscovery: RecordingProviderDiscoveryService(statuses: [
                .codex: Self.providerStatus(for: .codex, modelOptions: [modelOption])
            ])
        )
        await viewModel.refreshProviderStatuses()

        XCTAssertEqual(viewModel.defaultModel, "codex-fast")

        viewModel.defaultModel = "codex-fast"

        XCTAssertEqual(service.current.defaultModel, "gpt-5.4-mini")
    }

    // Switching the default model to Opus while effort is still at the universal
    // default (i.e. the user never touched the picker) should bump to Opus's
    // preferred `xhigh`, so the Settings picker reflects the same default a
    // fresh thread will actually receive.
    func testDefaultModelSetterUpgradesUntouchedEffortToPerModelDefault() async {
        let service = InMemorySettingsService()
        let viewModel = SettingsViewModel(
            settingsService: service,
            providerDiscovery: RecordingProviderDiscoveryService(statuses: [
                .claude: Self.providerStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions)
            ])
        )
        await viewModel.refreshProviderStatuses()
        XCTAssertEqual(service.current.effort, AppSettings.defaultEffortLevel)

        viewModel.defaultModel = "opus"

        XCTAssertEqual(service.current.defaultModel, "opus")
        XCTAssertEqual(service.current.effort, "xhigh")
    }

    func testProviderExtraArgsHelpersCreateEntriesAndPreserveOtherProviders() {
        let service = InMemorySettingsService()
        service.update {
            $0.providerConfigs["other"] = ProviderCustomConfig(extraArgs: "--other")
        }
        let viewModel = SettingsViewModel(settingsService: service)

        XCTAssertNil(viewModel.providerExtraArgs(for: "claude"))

        viewModel.updateProviderExtraArgs(for: "claude", extraArgs: "--verbose")

        XCTAssertEqual(service.current.providerConfigs["claude"], ProviderCustomConfig(extraArgs: "--verbose"))
        XCTAssertEqual(service.current.providerConfigs["other"], ProviderCustomConfig(extraArgs: "--other"))
    }

    func testSoundNameFallsBackToGlassWhenStoredValueIsNil() {
        let service = InMemorySettingsService()
        service.update { $0.notifications.soundName = nil }
        let viewModel = SettingsViewModel(settingsService: service)

        XCTAssertEqual(viewModel.soundName, "Glass")
    }

    func testChangingSoundNamePreviewsNewSound() {
        let service = InMemorySettingsService()
        var previewedSounds: [String] = []
        let viewModel = SettingsViewModel(
            settingsService: service,
            soundPreviewer: { previewedSounds.append($0) }
        )

        viewModel.soundName = "Pop"

        XCTAssertEqual(service.current.notifications.soundName, "Pop")
        XCTAssertEqual(previewedSounds, ["Pop"])
    }

    func testSettingSameSoundNamePreviewsAgain() {
        let service = InMemorySettingsService()
        var previewedSounds: [String] = []
        let viewModel = SettingsViewModel(
            settingsService: service,
            soundPreviewer: { previewedSounds.append($0) }
        )

        viewModel.soundName = "Glass"

        XCTAssertEqual(service.current.notifications.soundName, "Glass")
        XCTAssertEqual(previewedSounds, ["Glass"])
    }

    func testSoundNamePreviewRequiresNotificationsAndSoundEnabled() {
        let notificationsDisabledService = InMemorySettingsService()
        notificationsDisabledService.update { $0.notifications.enabled = false }
        var notificationsDisabledPreviews: [String] = []
        let notificationsDisabledViewModel = SettingsViewModel(
            settingsService: notificationsDisabledService,
            soundPreviewer: { notificationsDisabledPreviews.append($0) }
        )

        notificationsDisabledViewModel.soundName = "Pop"

        let soundDisabledService = InMemorySettingsService()
        soundDisabledService.update { $0.notifications.sound = false }
        var soundDisabledPreviews: [String] = []
        let soundDisabledViewModel = SettingsViewModel(
            settingsService: soundDisabledService,
            soundPreviewer: { soundDisabledPreviews.append($0) }
        )

        soundDisabledViewModel.soundName = "Tink"

        XCTAssertEqual(notificationsDisabledService.current.notifications.soundName, "Pop")
        XCTAssertTrue(notificationsDisabledPreviews.isEmpty)
        XCTAssertEqual(soundDisabledService.current.notifications.soundName, "Tink")
        XCTAssertTrue(soundDisabledPreviews.isEmpty)
    }

    func testInvalidSoundNameFallsBackAndDoesNotPreview() {
        let service = InMemorySettingsService()
        var previewedSounds: [String] = []
        let viewModel = SettingsViewModel(
            settingsService: service,
            soundPreviewer: { previewedSounds.append($0) }
        )

        viewModel.soundName = "Bogus"

        XCTAssertEqual(service.current.notifications.soundName, "Glass")
        XCTAssertTrue(previewedSounds.isEmpty)
    }
}

private extension SettingsViewModelTests {
    static func providerStatus(
        for providerId: AgentCLIKit.AgentProviderID,
        modelOptions: [AgentCLIKit.AgentModelOption]
    ) -> AgentCLIKit.AgentProviderStatus {
        AgentCLIKit.AgentProviderStatus(
            providerId: providerId,
            definition: providerId == .claude
                ? AgentCLIKit.ClaudeProviderDefinition.definition
                : AgentCLIKit.CodexProviderDefinition.definition,
            installation: .installed,
            availability: AgentCLIKit.AgentProviderAvailability(providerId: providerId, executablePath: "/usr/local/bin/\(providerId.rawValue)"),
            setup: .ready,
            modelOptions: modelOptions
        )
    }
}

private actor RecordingProviderDiscoveryService: AgentCLIKit.AgentProviderDiscoveryService {
    private let statuses: [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus]
    private var providerStatusesCallCount = 0

    init(statuses: [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus]) {
        self.statuses = statuses
    }

    func providerStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] {
        providerStatusesCallCount += 1
        return statuses
    }

    func installedProviderStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] {
        statuses.filter { $0.value.isInstalled }
    }

    func availableProviderStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus] {
        statuses.filter { $0.value.isEnabled && $0.value.installation != .missing }
    }

    func modelOptions(for providerId: AgentCLIKit.AgentProviderID) async -> [AgentCLIKit.AgentModelOption] {
        statuses[providerId]?.modelOptions ?? AgentCLIKit.AgentDefaultModelOptions.providerDefault(for: providerId)
    }

    func stableProviderOrdering() async -> [AgentCLIKit.AgentProviderID] {
        [.claude, .codex]
    }

    func providerStatusesInvocations() -> Int {
        providerStatusesCallCount
    }
}
