import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testRefreshHarnessStatusesLoadsDetectedStatusAndHelperMetadata() async {
        let discovery = RecordingHarnessDiscoveryService(statuses: [
            .claude: AgentCLIKit.AgentHarnessStatus(
                harnessId: .claude,
                definition: AgentCLIKit.ClaudeHarnessDefinition.definition,
                installation: .installed,
                availability: AgentCLIKit.AgentHarnessAvailability(
                    harnessId: .claude,
                    executablePath: "/usr/local/bin/claude",
                    versionDescription: "2.1.104"
                ),
                setup: .ready,
                modelOptions: AgentModelOptionTestFixtures.claudeModelOptions
            )
        ])
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(),
            harnessDiscovery: discovery
        )

        await viewModel.refreshHarnessStatuses()
        let harnessStatusesInvocations = await discovery.harnessStatusesInvocations()

        XCTAssertEqual(viewModel.harnessStatus(for: "claude")?.installation, .installed)
        XCTAssertEqual(viewModel.shortStatusLabel(for: viewModel.harnessStatus(for: "claude")), "Ready")
        XCTAssertEqual(viewModel.statusDescription(for: viewModel.harnessStatus(for: "claude")), "2.1.104 at /usr/local/bin/claude")
        XCTAssertEqual(viewModel.installCommand(for: "claude"), "curl -fsSL https://claude.ai/install.sh | bash")
        XCTAssertEqual(harnessStatusesInvocations, 1)
    }

    func testRefreshHarnessStatusesIfNeededOnlyLoadsOnce() async {
        let discovery = RecordingHarnessDiscoveryService(statuses: [
            .claude: AgentCLIKit.AgentHarnessStatus(
                harnessId: .claude,
                definition: AgentCLIKit.ClaudeHarnessDefinition.definition,
                installation: .missing,
                availability: AgentCLIKit.AgentHarnessAvailability(harnessId: .claude, executablePath: nil),
                setup: .ready,
                modelOptions: AgentModelOptionTestFixtures.claudeModelOptions
            )
        ])
        let viewModel = SettingsViewModel(
            settingsService: InMemorySettingsService(),
            harnessDiscovery: discovery
        )

        await viewModel.refreshHarnessStatusesIfNeeded()
        await viewModel.refreshHarnessStatusesIfNeeded()
        let harnessStatusesInvocations = await discovery.harnessStatusesInvocations()

        XCTAssertEqual(viewModel.harnessStatus(for: "claude")?.installation, .missing)
        XCTAssertEqual(harnessStatusesInvocations, 1)
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
            $0.lastSettingsPage = .terminal
            $0.defaultModel = "opus"
            $0.permissionMode = "acceptEdits"
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
        }
        let viewModel = SettingsViewModel(settingsService: service)

        XCTAssertEqual(viewModel.lastSettingsPage, .terminal)
        let agent = viewModel.threadDefaultAgentPresentation
        XCTAssertEqual(agent.effective.harness.id, "claude")
        // The stored alias resolves against the static catalog, mirroring what a discovery-backed screen shows.
        XCTAssertEqual(agent.selection.modelID, "claude-opus-5-5")
        XCTAssertEqual(agent.selection.effortValue, "high")
        XCTAssertEqual(viewModel.permissionMode, "acceptEdits")
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

        viewModel.lastSettingsPage = .git
        viewModel.permissionMode = "acceptEdits"
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

        XCTAssertEqual(service.current.lastSettingsPage, .git)
        XCTAssertEqual(service.current.permissionMode, "acceptEdits")
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

    func testLastSettingsPageSetterIgnoresUnchangedValue() {
        var settings = AppSettings()
        settings.lastSettingsPage = .notifications
        let service = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(settingsService: service)

        viewModel.lastSettingsPage = .notifications

        XCTAssertEqual(service.updateCount, 0)
        XCTAssertEqual(service.current.lastSettingsPage, .notifications)
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

extension SettingsViewModelTests {
    static func harnessStatus(
        for harnessId: AgentCLIKit.AgentHarnessID,
        installation: AgentCLIKit.AgentHarnessInstallationState = .installed,
        isEnabled: Bool = true,
        setup: AgentCLIKit.AgentHarnessReadinessState = .ready,
        modelOptions: [AgentCLIKit.AgentModelOption]
    ) -> AgentCLIKit.AgentHarnessStatus {
        AgentCLIKit.AgentHarnessStatus(
            harnessId: harnessId,
            definition: harnessId == .opencode ? AgentCLIKit.OpenCodeHarnessDefinition.definition
                : harnessId == .claude ? AgentCLIKit.ClaudeHarnessDefinition.definition : AgentCLIKit.CodexHarnessDefinition.definition,
            installation: installation,
            availability: AgentCLIKit.AgentHarnessAvailability(harnessId: harnessId, executablePath: "/usr/local/bin/\(harnessId.rawValue)"),
            isEnabled: isEnabled,
            setup: setup,
            modelOptions: modelOptions
        )
    }
}

actor RecordingHarnessDiscoveryService: AgentCLIKit.AgentHarnessDiscoveryService {
    private let statuses: [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus]
    private var harnessStatusesCallCount = 0
    private(set) var requestedProjectURLs: [URL?] = []

    init(statuses: [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus]) {
        self.statuses = statuses
    }

    func harnessStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus] {
        harnessStatusesCallCount += 1
        requestedProjectURLs.append(projectURL)
        return statuses
    }

    func installedHarnessStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus] {
        statuses.filter { $0.value.isInstalled }
    }

    func availableHarnessStatuses(projectURL: URL?) async -> [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus] {
        statuses.filter { $0.value.isEnabled && $0.value.installation != .missing }
    }

    func modelOptions(for harnessId: AgentCLIKit.AgentHarnessID) async -> [AgentCLIKit.AgentModelOption] {
        statuses[harnessId]?.modelOptions ?? AgentCLIKit.AgentDefaultModelOptions.harnessDefault(for: harnessId)
    }

    func stableHarnessOrdering() async -> [AgentCLIKit.AgentHarnessID] {
        [.claude, .codex, .opencode]
    }

    func harnessStatusesInvocations() -> Int {
        harnessStatusesCallCount
    }
}
