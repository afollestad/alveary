import AgentCLIKit
import Testing

@testable import Alveary

@MainActor
struct ReviewTeamSettingsDraftTests {
    @Test func `lead edits stay local until the whole team is saved`() async {
        var settings = AppSettings()
        settings.pullRequestReviewPermissionMode = "acceptEdits"
        let (viewModel, service) = await makeViewModel(settings: settings)
        let original = service.current
        let updates = service.updateCount
        var draft = service.current
        draft.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer", providerID: "claude", model: "sonnet", effort: "high")
        ]

        viewModel.setReviewTeamLeadProvider("codex", in: &draft)
        viewModel.setReviewTeamLeadModel("gpt-5.5", in: &draft)

        #expect(service.current == original)
        #expect(service.updateCount == updates)
        viewModel.setPullRequestReviewTeam(draft)
        #expect(service.updateCount == updates + 1)
        #expect(service.current.pullRequestReviewProvider == "codex")
        #expect(service.current.pullRequestReviewModel == "gpt-5.5")
        #expect(service.current.pullRequestReviewPermissionMode == nil)
        #expect(service.current.pullRequestReviewPeers == draft.pullRequestReviewPeers)
    }

    @Test func `saving team edits preserves newer feedback and thread settings`() async {
        let (viewModel, service) = await makeViewModel()
        var draft = viewModel.reviewTeamEditorSettings()
        viewModel.setReviewTeamLeadProvider("codex", in: &draft)
        service.update {
            $0.pullRequestAddressFeedbackProvider = "claude"
            $0.pullRequestAddressFeedbackModel = "haiku"
            $0.pullRequestAddressFeedbackPermissionMode = "acceptEdits"
            $0.defaultModel = "opus"
        }

        viewModel.setPullRequestReviewTeam(draft)

        #expect(service.current.pullRequestAddressFeedbackProvider == "claude")
        #expect(service.current.pullRequestAddressFeedbackModel == "haiku")
        #expect(service.current.pullRequestAddressFeedbackPermissionMode == "acceptEdits")
        #expect(service.current.defaultModel == "opus")
    }

    @Test func `unchanged lead retains inheritance and single review permissions`() async {
        var settings = AppSettings()
        settings.pullRequestReviewPermissionMode = "acceptEdits"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer", providerID: "codex", model: "gpt-5.5", effort: "medium")
        ]
        let (viewModel, service) = await makeViewModel(settings: settings)
        let draft = viewModel.reviewTeamEditorSettings()

        viewModel.setPullRequestReviewTeam(draft)

        #expect(service.current.pullRequestReviewProvider == nil)
        #expect(service.current.pullRequestReviewModel == nil)
        #expect(service.current.pullRequestReviewEffort == nil)
        #expect(service.current.pullRequestReviewPermissionMode == "acceptEdits")
    }

    @Test func `unavailable lead pins remain selectable until explicitly repaired`() async {
        var settings = AppSettings()
        settings.pullRequestReviewMode = .reviewTeam
        settings.pullRequestReviewProvider = "codex"
        settings.setProvider("codex", enabled: false)
        settings.pullRequestReviewModel = "retired-model"
        settings.pullRequestReviewEffort = "retired-effort"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "peer", providerID: "claude", model: "sonnet", effort: "high")
        ]
        let (viewModel, _) = await makeViewModel(settings: settings)
        let draft = viewModel.reviewTeamEditorSettings()

        #expect(viewModel.reviewTeamLeadProviderOptions(draft).contains("codex"))
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
        let peer = PullRequestReviewPeer(id: "peer", providerID: "codex", model: "gpt-5.5", effort: "medium")
        var draft = service.current
        draft.pullRequestReviewPeers = [peer]
        #expect(viewModel.pullRequestReviewTeamSettingsStatus(peers: [peer], settings: draft) == .ready)
        viewModel.setReviewTeamLeadProvider("codex", in: &draft)
        viewModel.setReviewTeamLeadModel("gpt-5.5", in: &draft)

        guard case .needsAttention(let message) = viewModel.pullRequestReviewTeamSettingsStatus(peers: [peer], settings: draft) else {
            Issue.record("Duplicating the lead must block Save")
            return
        }
        #expect(message.contains("same agent and model"))
        let suggested = try #require(viewModel.defaultPullRequestReviewPeer(providerID: "codex", excluding: [], settings: draft))
        #expect(suggested.model != "gpt-5.5")
    }

    private func makeViewModel(settings: AppSettings = AppSettings()) async -> (SettingsViewModel, InMemorySettingsService) {
        let service = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(
            settingsService: service,
            providerDiscovery: RecordingProviderDiscoveryService(statuses: [
                .claude: SettingsViewModelTests.providerStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions),
                .codex: SettingsViewModelTests.providerStatus(for: .codex, modelOptions: AgentModelOptionTestFixtures.codexModelOptions)
            ])
        )
        await viewModel.refreshProviderStatuses()
        return (viewModel, service)
    }
}
