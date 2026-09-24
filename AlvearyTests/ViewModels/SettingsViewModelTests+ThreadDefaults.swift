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
        XCTAssertEqual(viewModel.threadDefaultAgentPresentation.selection.modelID, "sonnet")
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

        XCTAssertEqual(viewModel.threadDefaultAgentPresentation.availability, .unavailable)
        XCTAssertTrue(viewModel.threadDefaultHarnessIDs.isEmpty)
        XCTAssertEqual(service.current.defaultHarness, "claude")
    }

    func testThreadDefaultAgentPickAcrossHarnessesWritesOneCoherentDefault() async {
        var settings = AppSettings()
        settings.defaultModel = "sonnet"
        settings.permissionMode = "acceptEdits"
        settings.effort = "high"
        let service = InMemorySettingsService(current: settings)
        let viewModel = makeThreadDefaultViewModel(service: service)
        await viewModel.refreshHarnessStatuses()
        let updateCount = service.updateCount

        pickThreadDefaultModel("gpt-5.4-mini", harnessID: "codex", in: viewModel)

        XCTAssertEqual(service.updateCount, updateCount + 1)
        XCTAssertEqual(service.current.defaultHarness, "codex")
        XCTAssertEqual(service.current.defaultModel, "gpt-5.4-mini")
        XCTAssertEqual(service.current.permissionMode, AppSettings.defaultPermissionMode(forHarness: "codex"))
        XCTAssertEqual(service.current.effort, "low")
    }

    func testThreadDefaultAgentCheckedRowIsANoOpAndEffortDragKeepsTheModel() async {
        let service = InMemorySettingsService()
        let viewModel = makeThreadDefaultViewModel(service: service)
        await viewModel.refreshHarnessStatuses()
        let storedModel = service.current.defaultModel
        let updateCount = service.updateCount
        let presentation = viewModel.threadDefaultAgentPresentation
        let configuration = ReasoningConfiguration(presentation: presentation) { viewModel.applyThreadDefaultAgent($0) }

        guard case .unchanged = configuration.onModelChange(.init(harnessID: "claude", modelID: presentation.selection.modelID)) else {
            return XCTFail("Re-picking the checked row should not write.")
        }
        XCTAssertEqual(service.updateCount, updateCount)
        XCTAssertTrue(configuration.onEffortChange("max"))

        XCTAssertEqual(service.current.defaultModel, storedModel)
        XCTAssertEqual(service.current.effort, "max")
    }

    /// A drag pins the resolved agent, which differs from a stored default the Harnesses tab disabled.
    func testThreadDefaultEffortDragKeepsTheDraggedEffortWhenTheStoredHarnessIsDisabled() async {
        var settings = AppSettings()
        settings.defaultHarness = "codex"
        let service = InMemorySettingsService(current: settings)
        let viewModel = makeThreadDefaultViewModel(service: service)
        await viewModel.refreshHarnessStatuses()
        service.update { $0.setHarness("codex", enabled: false) }
        let configuration = ReasoningConfiguration(presentation: viewModel.threadDefaultAgentPresentation) {
            viewModel.applyThreadDefaultAgent($0)
        }

        XCTAssertTrue(configuration.onEffortChange("max"))

        XCTAssertEqual(service.current.defaultHarness, "claude")
        XCTAssertEqual(service.current.effort, "max")
    }

    // A pick must not silently retain an effort the new model rejects.
    func testThreadDefaultModelPickCoercesEffortWhenNewModelDoesNotSupportIt() async {
        let limitedSonnet = AgentCLIKit.AgentModelOption(
            harnessId: .claude,
            id: "sonnet",
            model: "sonnet",
            label: "Sonnet",
            supportedEffortOptions: [AgentModelOptionTestFixtures.medium, AgentModelOptionTestFixtures.high],
            defaultEffortOption: AgentModelOptionTestFixtures.high
        )
        let opus = AgentCLIKit.AgentModelOption(
            harnessId: .claude,
            id: "opus",
            model: "opus",
            label: "Opus",
            supportedEffortOptions: AgentModelOptionTestFixtures.claudeOpusEfforts,
            defaultEffortOption: AgentModelOptionTestFixtures.high
        )
        let service = InMemorySettingsService()
        service.update {
            $0.defaultModel = "opus"
            $0.effort = "xhigh"
        }
        let viewModel = makeThreadDefaultViewModel(service: service, claudeModelOptions: [limitedSonnet, opus])
        await viewModel.refreshHarnessStatuses()

        pickThreadDefaultModel("sonnet", in: viewModel)

        XCTAssertEqual(service.current.defaultModel, "sonnet")
        XCTAssertEqual(service.current.effort, "high")
    }

    func testThreadDefaultModelPickPreservesEffortWhenNewModelStillSupportsIt() async {
        let service = InMemorySettingsService()
        service.update {
            $0.defaultModel = "claude-sonnet-5"
            $0.effort = "high"
        }
        let viewModel = makeThreadDefaultViewModel(service: service, claudeModelOptions: Self.staticClaudeModelOptions)
        await viewModel.refreshHarnessStatuses()

        pickThreadDefaultModel("opus", in: viewModel)

        XCTAssertEqual(service.current.defaultModel, "claude-opus-5-5")
        XCTAssertEqual(service.current.effort, "high")
    }

    func testThreadDefaultModelShowsOptionIDAndStoresHarnessModelValue() async {
        let options = [
            AgentCLIKit.AgentModelOption(
                harnessId: .codex,
                id: "codex-fast",
                model: "gpt-5.4-mini",
                label: "GPT-5.4-Mini",
                isDefault: true,
                supportedEffortOptions: AgentModelOptionTestFixtures.codexDefaultEfforts,
                defaultEffortOption: AgentModelOptionTestFixtures.medium
            ),
            AgentCLIKit.AgentModelOption(harnessId: .codex, id: "codex-deep", model: "gpt-5.5", label: "GPT-5.5")
        ]
        let service = InMemorySettingsService()
        service.update {
            $0.defaultHarness = "codex"
            $0.defaultModel = "gpt-5.5"
        }
        let viewModel = SettingsViewModel(
            settingsService: service,
            harnessDiscovery: RecordingHarnessDiscoveryService(statuses: [.codex: Self.harnessStatus(for: .codex, modelOptions: options)])
        )
        await viewModel.refreshHarnessStatuses()

        XCTAssertEqual(viewModel.threadDefaultAgentPresentation.selection.modelID, "codex-deep")

        pickThreadDefaultModel("codex-fast", harnessID: "codex", in: viewModel)

        XCTAssertEqual(service.current.defaultModel, "gpt-5.4-mini")
    }

    /// Switching models with untouched effort uses that version's default; older explicit pins retain their own default.
    func testThreadDefaultModelPickUsesPerModelDefaultForUntouchedEffort() async {
        let service = InMemorySettingsService()
        let viewModel = makeThreadDefaultViewModel(service: service, claudeModelOptions: Self.staticClaudeModelOptions)
        await viewModel.refreshHarnessStatuses()
        for (model, expectedModel, expectedEffort) in [
            ("opus", "claude-opus-5-5", "medium"),
            ("claude-opus-5", "claude-opus-5", "high")
        ] {
            service.update {
                $0.defaultModel = "claude-sonnet-5"
                $0.effort = AppSettings.defaultEffortLevel
            }

            pickThreadDefaultModel(model, in: viewModel)

            XCTAssertEqual(service.current.defaultModel, expectedModel)
            XCTAssertEqual(service.current.effort, expectedEffort)
        }
    }

    private static var staticClaudeModelOptions: [AgentCLIKit.AgentModelOption] {
        AgentCLIKit.AgentDefaultModelOptions.staticOptions(for: .claude)
    }

    private func makeThreadDefaultViewModel(
        service: InMemorySettingsService,
        claudeModelOptions: [AgentCLIKit.AgentModelOption] = AgentModelOptionTestFixtures.claudeModelOptions
    ) -> SettingsViewModel {
        SettingsViewModel(
            settingsService: service,
            harnessDiscovery: RecordingHarnessDiscoveryService(statuses: [
                .claude: Self.harnessStatus(for: .claude, modelOptions: claudeModelOptions),
                .codex: Self.harnessStatus(for: .codex, modelOptions: AgentModelOptionTestFixtures.codexModelOptions)
            ])
        )
    }

    private func pickThreadDefaultModel(_ model: String, harnessID: String = "claude", in viewModel: SettingsViewModel) {
        pickAgentModel(model, harnessID: harnessID, in: viewModel.threadDefaultAgentPresentation) {
            viewModel.applyThreadDefaultAgent($0)
        }
    }
}
