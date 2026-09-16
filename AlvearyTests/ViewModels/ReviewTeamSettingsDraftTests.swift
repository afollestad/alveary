import AgentCLIKit
import Testing

@testable import Alveary

@MainActor
struct ReviewTeamSettingsDraftTests {
    @Test func `registered read only harnesses reach utility and review selections and resolve their models`() async throws {
        for definition in AgentHarnessRegistry.builtInDefinitions {
            let harnessID = definition.id.rawValue
            let supported = definition.capabilities.supportsReadOnlyOneShotPrompts
            #expect(HarnessFeaturePolicy.supportsReadOnlyOneShotPrompts(harnessID: harnessID) == supported)
            #expect(HarnessFeaturePolicy.supportsIsolatedReviewWorkers(harnessID: harnessID) == supported)
            #expect(HarnessFeaturePolicy.declared(harnessID: harnessID).supportsReadOnlyOneShotPrompts == supported)
            guard supported else { continue }
            let efforts: [AgentHarnessOption] = definition.id == .opencode ? [] : [.init(value: "medium", label: "Medium", description: "")]
            let model = AgentModelOption(
                harnessId: definition.id, id: "provider/exact-model", model: "provider/exact-model", label: "Exact model",
                supportedEffortOptions: efforts
            )
            let status = SettingsViewModelTests.harnessStatus(for: definition.id, modelOptions: [model])
            var settings = AppSettings()
            settings.defaultHarness = harnessID
            settings.defaultModel = model.id
            settings.effort = definition.id == .opencode ? AppSettings.openCodeDefaultEffort : "medium"
            let viewModel = SettingsViewModel(
                settingsService: InMemorySettingsService(current: settings),
                harnessDiscovery: RecordingHarnessDiscoveryService(statuses: [definition.id: status])
            )
            await viewModel.refreshHarnessStatuses()

            #expect(viewModel.utilityHarnessOptions.contains(harnessID))
            #expect(viewModel.utilityUnavailableMessage == nil)
            #expect(viewModel.reviewTeamLeadHarnessOptions(settings).contains(harnessID))
            #expect(viewModel.pullRequestReviewPeerHarnessOptions(including: harnessID).contains(harnessID))
            let worker = try PullRequestReviewTeamResolver.resolveLead(settings: settings, harnessStatuses: [definition.id: status])
            #expect(worker.harnessID == harnessID)
            #expect(worker.launchModel == model.model)
            #expect(worker.effort == settings.effort)
        }
        #expect(!HarnessFeaturePolicy.supportsReadOnlyOneShotPrompts(harnessID: "unregistered"))
        #expect(!HarnessFeaturePolicy.supportsIsolatedReviewWorkers(harnessID: "unregistered"))
    }

    @Test func `lead edits stay local until the whole team is saved`() async {
        var settings = AppSettings()
        settings.pullRequestReviewPermissionMode = "acceptEdits"
        let (viewModel, service) = await makeViewModel(settings: settings)
        let original = service.current
        let updates = service.updateCount
        var draft = service.current
        draft.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer", harnessID: "claude", model: "sonnet", effort: "high")
        ]

        viewModel.setReviewTeamLeadHarness("codex", in: &draft)
        viewModel.setReviewTeamLeadModel("gpt-5.5", in: &draft)

        #expect(service.current == original)
        #expect(service.updateCount == updates)
        viewModel.setPullRequestReviewTeam(draft)
        #expect(service.updateCount == updates + 1)
        #expect(service.current.pullRequestReviewHarness == "codex")
        #expect(service.current.pullRequestReviewModel == "gpt-5.5")
        #expect(service.current.pullRequestReviewPermissionMode == nil)
        #expect(service.current.pullRequestReviewPeers == draft.pullRequestReviewPeers)
    }

    @Test func `saving team edits preserves newer feedback and thread settings`() async {
        let (viewModel, service) = await makeViewModel()
        var draft = viewModel.reviewTeamEditorSettings()
        viewModel.setReviewTeamLeadHarness("codex", in: &draft)
        service.update {
            $0.pullRequestAddressFeedbackHarness = "claude"
            $0.pullRequestAddressFeedbackModel = "haiku"
            $0.pullRequestAddressFeedbackPermissionMode = "acceptEdits"
            $0.defaultModel = "opus"
        }

        viewModel.setPullRequestReviewTeam(draft)

        #expect(service.current.pullRequestAddressFeedbackHarness == "claude")
        #expect(service.current.pullRequestAddressFeedbackModel == "haiku")
        #expect(service.current.pullRequestAddressFeedbackPermissionMode == "acceptEdits")
        #expect(service.current.defaultModel == "opus")
    }

    @Test func `unchanged lead retains inheritance and single review permissions`() async {
        var settings = AppSettings()
        settings.pullRequestReviewPermissionMode = "acceptEdits"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer", harnessID: "codex", model: "gpt-5.5", effort: "medium")
        ]
        let (viewModel, service) = await makeViewModel(settings: settings)
        let draft = viewModel.reviewTeamEditorSettings()

        viewModel.setPullRequestReviewTeam(draft)

        #expect(service.current.pullRequestReviewHarness == nil)
        #expect(service.current.pullRequestReviewModel == nil)
        #expect(service.current.pullRequestReviewEffort == nil)
        #expect(service.current.pullRequestReviewPermissionMode == "acceptEdits")
    }

    @Test func `unavailable lead pins remain selectable until explicitly repaired`() async {
        var settings = AppSettings()
        settings.pullRequestReviewMode = .reviewTeam
        settings.pullRequestReviewHarness = "codex"
        settings.setHarness("codex", enabled: false)
        settings.pullRequestReviewModel = "retired-model"
        settings.pullRequestReviewEffort = "retired-effort"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer", harnessID: "claude", model: "sonnet", effort: "high")
        ]
        let (viewModel, _) = await makeViewModel(settings: settings)
        let draft = viewModel.reviewTeamEditorSettings()

        #expect(viewModel.reviewTeamLeadHarnessOptions(draft).contains("codex"))
        #expect(viewModel.reviewTeamLeadModelSelection(draft) == "retired-model")
        #expect(viewModel.reviewTeamLeadModelOptions(draft).contains("retired-model"))
        #expect(viewModel.reviewTeamLeadEffortOptions(draft).contains("retired-effort"))
        guard case .needsAttention = viewModel.pullRequestReviewTeamSettingsStatus(
            peers: draft.pullRequestReviewPeers, settings: draft
        ) else {
            Issue.record("Unavailable lead must block Save")
            return
        }
    }

    @Test func `team validation and peer suggestions use the unsaved lead`() async throws {
        let (viewModel, service) = await makeViewModel()
        let peer = PullRequestReviewPeer(id: "peer", harnessID: "codex", model: "gpt-5.5", effort: "medium")
        var draft = service.current
        draft.pullRequestReviewPeers = [peer]
        #expect(viewModel.pullRequestReviewTeamSettingsStatus(peers: [peer], settings: draft) == .ready)
        viewModel.setReviewTeamLeadHarness("codex", in: &draft)
        viewModel.setReviewTeamLeadModel("gpt-5.5", in: &draft)

        guard case .needsAttention(let message) = viewModel.pullRequestReviewTeamSettingsStatus(peers: [peer], settings: draft) else {
            Issue.record("Duplicating the lead must block Save")
            return
        }
        #expect(message.contains("same harness and model"))
        let suggested = try #require(viewModel.defaultPullRequestReviewPeer(harnessID: "codex", excluding: [], settings: draft))
        #expect(suggested.model != "gpt-5.5")
    }

    @Test func `openCode lead and peer choices retain exact models and optional variants`() async throws {
        var settings = AppSettings()
        settings.defaultHarness = "opencode"
        settings.defaultModel = "provider/text"
        settings.effort = AppSettings.openCodeDefaultEffort
        let (viewModel, service) = await makeViewModel(settings: settings)
        let original = service.current
        var draft = viewModel.reviewTeamEditorSettings()

        #expect(draft.pullRequestReviewHarness == nil)
        #expect(viewModel.reviewTeamDraftLead(draft).model == "provider/text")
        #expect(viewModel.reviewTeamLeadHarnessOptions(draft).contains("opencode"))
        #expect(viewModel.pullRequestReviewPeerHarnessOptions(including: "opencode").contains("opencode"))
        #expect(viewModel.reviewTeamLeadModelOptions(draft).contains("provider/text"))
        let peer = try #require(viewModel.defaultPullRequestReviewPeer(harnessID: "opencode", excluding: [], settings: draft))
        #expect(peer.model == "provider/reasoning")
        #expect(peer.effort == AppSettings.openCodeDefaultEffort)
        #expect(viewModel.pullRequestReviewPeerEffortOptions(peer) == [AppSettings.openCodeDefaultEffort, "native"])
        #expect(viewModel.pullRequestReviewPeerEffortLabel(peer.effort, peer: peer) == "Default")
        draft.pullRequestReviewPeers = [peer]
        #expect(viewModel.pullRequestReviewTeamSettingsStatus(peers: [peer], settings: draft) == .ready)

        viewModel.setReviewTeamLeadModel("provider/reasoning", in: &draft)
        #expect(draft.pullRequestReviewEffort == AppSettings.openCodeDefaultEffort)
        #expect(viewModel.pullRequestReviewTeamSettingsStatus(peers: [peer], settings: draft) != .ready)
        #expect(service.current == original)
    }

    private func makeViewModel(settings: AppSettings = AppSettings()) async -> (SettingsViewModel, InMemorySettingsService) {
        let service = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(
            settingsService: service,
            harnessDiscovery: RecordingHarnessDiscoveryService(statuses: [
                .claude: SettingsViewModelTests.harnessStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions),
                .codex: SettingsViewModelTests.harnessStatus(for: .codex, modelOptions: AgentModelOptionTestFixtures.codexModelOptions),
                .opencode: SettingsViewModelTests.harnessStatus(for: .opencode, modelOptions: [
                    AgentModelOption(harnessId: .opencode, id: "provider/text", model: "provider/text", label: "Text"),
                    AgentModelOption(
                        harnessId: .opencode, id: "provider/reasoning", model: "provider/reasoning", label: "Reasoning",
                        supportedEffortOptions: [.init(value: "native", label: "Native", description: "")]
                    )
                ])
            ])
        )
        await viewModel.refreshHarnessStatuses()
        return (viewModel, service)
    }
}
