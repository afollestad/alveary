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

            #expect(viewModel.utilityAgentPresentation.harnesses.map(\.id).contains(harnessID))
            #expect(viewModel.utilityUnavailableMessage == nil)
            let leadGroup = viewModel.reviewTeamLeadPresentation(settings).modelGroups.first { $0.harnessID == harnessID }
            #expect(leadGroup?.options.map(\.value) == [model.id])
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

        pickLeadModel("gpt-5.5", harnessID: "codex", in: &draft, viewModel: viewModel)

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
        pickLeadModel("gpt-5.5", harnessID: "codex", in: &draft, viewModel: viewModel)
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

        let lead = viewModel.reviewTeamLeadPresentation(draft)
        #expect(lead.pins == .init(harnessID: "codex", model: "retired-model", effort: "retired-effort"))
        #expect(lead.effective.harness.id == "codex")
        #expect(lead.selection.modelID == "retired-model")
        #expect(lead.selection.effortOptions.isEmpty)
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
        pickLeadModel("gpt-5.5", harnessID: "codex", in: &draft, viewModel: viewModel)

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
        let leadGroup = viewModel.reviewTeamLeadPresentation(draft).modelGroups.first { $0.harnessID == "opencode" }
        #expect(leadGroup?.options.map(\.value) == ["provider/text", "provider/reasoning"])
        let peer = try #require(viewModel.defaultPullRequestReviewPeer(harnessID: "opencode", excluding: [], settings: draft))
        #expect(peer.model == "provider/reasoning")
        #expect(peer.effort == AppSettings.openCodeDefaultEffort)
        let peerSelection = viewModel.reviewTeamPeerPresentation(peer).selection
        #expect(peerSelection.effortOptions.map(\.value) == [AppSettings.openCodeDefaultEffort, "native"])
        #expect(peerSelection.effortTitle == "Default")
        let defaultPeer = PullRequestReviewPeer(
            id: "default", harnessID: "opencode", model: AppSettings.defaultModelValue, effort: AppSettings.openCodeDefaultEffort
        )
        let defaultPeerPresentation = viewModel.reviewTeamPeerPresentation(defaultPeer)
        #expect(defaultPeerPresentation.selection.modelID == AppSettings.defaultModelValue)
        let defaultPeerGroup = defaultPeerPresentation.modelGroups.first { $0.harnessID == "opencode" }
        #expect(defaultPeerGroup?.options.map(\.value) == ["provider/text", "provider/reasoning", AppSettings.defaultModelValue])
        draft.pullRequestReviewPeers = [peer]
        #expect(viewModel.pullRequestReviewTeamSettingsStatus(peers: [peer], settings: draft) == .ready)

        pickLeadModel("provider/reasoning", harnessID: "opencode", in: &draft, viewModel: viewModel)
        #expect(draft.pullRequestReviewEffort == AppSettings.openCodeDefaultEffort)
        #expect(viewModel.pullRequestReviewTeamSettingsStatus(peers: [peer], settings: draft) != .ready)
        #expect(service.current == original)
    }

    @Test func `lead inherit row clears every pin and pinning the inherited harness keeps review permissions`() async {
        var settings = AppSettings()
        settings.pullRequestReviewPermissionMode = "acceptEdits"
        let (viewModel, service) = await makeViewModel(settings: settings)
        var draft = service.current
        draft.pullRequestReviewPeers = [PullRequestReviewPeer(id: "peer", harnessID: "codex", model: "gpt-5.5", effort: "medium")]

        pickLeadModel("opus", harnessID: "claude", in: &draft, viewModel: viewModel)
        viewModel.setPullRequestReviewTeam(draft)
        #expect(service.current.pullRequestReviewAgent == PullRequestAgentSettings(
            harness: "claude", model: "opus", effort: "medium", permissionMode: "acceptEdits"
        ))

        pickAgentInherit(in: viewModel.reviewTeamLeadPresentation(draft)) { viewModel.applyReviewTeamLead($0, in: &draft) }
        #expect(draft.pullRequestReviewHarness == nil)
        #expect(draft.pullRequestReviewModel == nil)
        #expect(draft.pullRequestReviewEffort == nil)
    }

    @Test func `peer picks apply by id without inheriting`() async {
        let (viewModel, service) = await makeViewModel()
        var draft = service.current
        let first = PullRequestReviewPeer(id: "first", harnessID: "claude", model: "sonnet", effort: "max")
        let second = PullRequestReviewPeer(id: "second", harnessID: "claude", model: "fable", effort: "high")
        draft.pullRequestReviewPeers = [first, second]
        let presentation = viewModel.reviewTeamPeerPresentation(second)
        #expect(presentation.inheritOption == nil)

        pickAgentModel("gpt-5.5", harnessID: "codex", in: presentation) { viewModel.applyReviewTeamPeer($0, id: second.id, in: &draft) }

        #expect(draft.pullRequestReviewPeers == [
            first,
            PullRequestReviewPeer(id: "second", harnessID: "codex", model: "gpt-5.5", effort: "high")
        ])
        #expect(service.current.pullRequestReviewPeers.isEmpty)
    }

    private func pickLeadModel(_ model: String, harnessID: String, in draft: inout AppSettings, viewModel: SettingsViewModel) {
        var edited = draft
        pickAgentModel(model, harnessID: harnessID, in: viewModel.reviewTeamLeadPresentation(draft)) {
            viewModel.applyReviewTeamLead($0, in: &edited)
        }
        draft = edited
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
