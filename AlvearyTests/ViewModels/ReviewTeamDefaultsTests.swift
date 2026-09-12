import AgentCLIKit
import Testing

@testable import Alveary

@MainActor
struct ReviewTeamDefaultsTests {
    @Test func `initial team uses the requested lineup without persisting before Save`() async {
        let (viewModel, service) = await makeViewModel()
        let original = service.current
        let updateCount = service.updateCount

        let draft = viewModel.reviewTeamEditorSettings()

        #expect(lineup(draft) == [
            "codex/gpt-5.6-sol/high",
            "codex/gpt-6-astra/max",
            "claude/claude-fable-5-1/max"
        ])
        #expect(viewModel.pullRequestReviewTeamSettingsStatus(peers: draft.pullRequestReviewPeers, settings: draft) == .ready)
        #expect(service.current == original)
        #expect(service.updateCount == updateCount)

        viewModel.setPullRequestReviewTeam(draft)

        #expect(lineup(service.current) == lineup(draft))
        #expect(service.current.pullRequestReviewPeers == draft.pullRequestReviewPeers)
        #expect(service.updateCount == updateCount + 1)
    }

    @Test(arguments: [AgentProviderID.codex, .claude], ReviewDefaultAvailabilityFault.allCases)
    func `unavailable providers are omitted instead of replaced`(
        providerID: AgentProviderID,
        fault: ReviewDefaultAvailabilityFault
    ) async {
        var settings = AppSettings()
        if fault == .disabledInSettings {
            settings.setProvider(providerID.rawValue, enabled: false)
        }
        var statuses = ReviewTeamDefaultsFixtures.statuses
        statuses[providerID] = fault == .absent ? nil : ReviewTeamDefaultsFixtures.status(for: providerID, fault: fault)
        let (viewModel, _) = await makeViewModel(settings: settings, statuses: statuses)

        let draft = viewModel.reviewTeamEditorSettings()
        let expected = providerID == .codex
            ? ["claude/claude-opus-5/high", "claude/claude-fable-5-1/max"]
            : ["codex/gpt-5.6-sol/high", "codex/gpt-6-astra/max"]

        #expect(lineup(draft) == expected)
        #expect(viewModel.pullRequestReviewTeamSettingsStatus(peers: draft.pullRequestReviewPeers, settings: draft) == .ready)
    }

    @Test(arguments: [false, true])
    func `unresolvable Sol falls back to Opus without replacing peers`(unsupportedEffort: Bool) async {
        var options = ReviewTeamDefaultsFixtures.models(for: .codex).filter { $0.model != "gpt-5.6-sol" }
        if unsupportedEffort {
            options.append(ReviewTeamDefaultsFixtures.model(providerID: .codex, id: "gpt-5.6-sol", efforts: ["medium"]))
        }
        var statuses = ReviewTeamDefaultsFixtures.statuses
        statuses[.codex] = ReviewTeamDefaultsFixtures.status(for: .codex, models: options)
        let (viewModel, _) = await makeViewModel(statuses: statuses)

        let draft = viewModel.reviewTeamEditorSettings()

        #expect(lineup(draft) == [
            "claude/claude-opus-5/high",
            "codex/gpt-6-astra/max",
            "claude/claude-fable-5-1/max"
        ])
        #expect(viewModel.pullRequestReviewTeamSettingsStatus(peers: draft.pullRequestReviewPeers, settings: draft) == .ready)
    }

    @Test func `an unavailable fallback lead stays requested and blocks Save`() async {
        let statuses: [AgentProviderID: AgentProviderStatus] = [
            .codex: ReviewTeamDefaultsFixtures.status(
                for: .codex,
                models: ReviewTeamDefaultsFixtures.models(for: .codex).filter { $0.model != "gpt-5.6-sol" }
            ),
            .claude: ReviewTeamDefaultsFixtures.status(
                for: .claude,
                models: ReviewTeamDefaultsFixtures.models(for: .claude).filter { $0.model != "claude-opus-5" }
            )
        ]
        let (viewModel, _) = await makeViewModel(statuses: statuses)

        let draft = viewModel.reviewTeamEditorSettings()

        #expect(lineup(draft).first == "claude/claude-opus-5/high")
        #expect(viewModel.pullRequestReviewTeamSettingsStatus(peers: draft.pullRequestReviewPeers, settings: draft)
            == .needsAttention("Lead uses claude-opus-5, which is not a concrete available model."))
    }

    @Test(arguments: [AgentProviderID.codex, .claude], [false, true])
    func `unavailable peer models or efforts remain requested`(providerID: AgentProviderID, unsupportedEffort: Bool) async {
        let modelID = providerID == .codex ? "gpt-6-astra" : "claude-fable-5-1"
        var options = ReviewTeamDefaultsFixtures.models(for: providerID).filter { $0.model != modelID }
        if unsupportedEffort {
            options.append(ReviewTeamDefaultsFixtures.model(providerID: providerID, id: modelID, efforts: ["high"]))
        }
        var statuses = ReviewTeamDefaultsFixtures.statuses
        statuses[providerID] = ReviewTeamDefaultsFixtures.status(for: providerID, models: options)
        let (viewModel, _) = await makeViewModel(statuses: statuses)

        let draft = viewModel.reviewTeamEditorSettings()

        #expect(lineup(draft) == [
            "codex/gpt-5.6-sol/high",
            "codex/gpt-6-astra/max",
            "claude/claude-fable-5-1/max"
        ])
        guard case .needsAttention = viewModel.pullRequestReviewTeamSettingsStatus(peers: draft.pullRequestReviewPeers, settings: draft) else {
            Issue.record("An unavailable exact peer selection must block Save")
            return
        }
    }

    @Test func `saved teams keep every pin even when discovery no longer resolves them`() async {
        var settings = AppSettings()
        settings.pullRequestReviewProvider = "codex"
        settings.pullRequestReviewModel = "retired-lead"
        settings.pullRequestReviewEffort = "ultra"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "saved-peer", providerID: "claude", model: "retired-peer", effort: "high")
        ]
        let (viewModel, service) = await makeViewModel(settings: settings, statuses: [:])
        let original = service.current
        let updateCount = service.updateCount

        let draft = viewModel.reviewTeamEditorSettings()

        #expect(draft == original)
        #expect(service.current == original)
        #expect(service.updateCount == updateCount)
    }

    private func makeViewModel(
        settings: AppSettings = AppSettings(),
        statuses: [AgentProviderID: AgentProviderStatus] = ReviewTeamDefaultsFixtures.statuses
    ) async -> (SettingsViewModel, InMemorySettingsService) {
        var settings = settings
        settings.pullRequestReviewMode = .reviewTeam
        let service = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(
            settingsService: service,
            providerDiscovery: RecordingProviderDiscoveryService(statuses: statuses)
        )
        await viewModel.refreshProviderStatuses()
        return (viewModel, service)
    }

    private func lineup(_ settings: AppSettings) -> [String] {
        let lead = "\(settings.pullRequestReviewProvider ?? "")/\(settings.pullRequestReviewModel ?? "")/\(settings.pullRequestReviewEffort ?? "")"
        return [lead] + settings.pullRequestReviewPeers.map { "\($0.providerID)/\($0.model)/\($0.effort)" }
    }
}

enum ReviewDefaultAvailabilityFault: CaseIterable, Sendable {
    case absent
    case disabledInSettings
    case disabledInDiscovery
    case missingInstallation
    case needsSetup
    case missingExecutable
    case blankExecutable
}

enum ReviewTeamDefaultsFixtures {
    static var statuses: [AgentProviderID: AgentProviderStatus] {
        [.codex: status(for: .codex), .claude: status(for: .claude)]
    }

    static func status(
        for providerID: AgentProviderID,
        models: [AgentModelOption]? = nil,
        fault: ReviewDefaultAvailabilityFault? = nil
    ) -> AgentProviderStatus {
        AgentProviderStatus(
            providerId: providerID,
            definition: providerID == .codex ? CodexProviderDefinition.definition : ClaudeProviderDefinition.definition,
            installation: fault == .missingInstallation ? .missing : .installed,
            availability: AgentProviderAvailability(
                providerId: providerID,
                executablePath: fault == .missingExecutable ? nil : fault == .blankExecutable ? " \n" : "/usr/local/bin/\(providerID.rawValue)"
            ),
            isEnabled: fault != .disabledInDiscovery,
            setup: fault == .needsSetup ? .needsSetup : .ready,
            modelOptions: models ?? self.models(for: providerID)
        )
    }

    static func models(for providerID: AgentProviderID) -> [AgentModelOption] {
        let ids = providerID == .codex ? ["gpt-5.6-sol", "gpt-6-astra"] : ["claude-opus-5", "claude-fable-5-1"]
        return ids.map { model(providerID: providerID, id: $0) }
    }

    static func model(providerID: AgentProviderID, id: String, efforts: [String] = ["high", "max"]) -> AgentModelOption {
        let effortOptions = efforts.map {
            AgentProviderOption(value: $0, label: $0.capitalized, description: "Use \($0) reasoning effort.")
        }
        let label = switch id {
        case "gpt-5.6-sol": "GPT-5.6-Sol"
        case "gpt-6-astra": "GPT-6-Astra"
        case "claude-opus-5": "Opus 5"
        case "claude-fable-5-1": "Fable 5.1"
        default: id
        }
        return AgentModelOption(
            providerId: providerID,
            id: id,
            model: id,
            label: label,
            supportedEffortOptions: effortOptions,
            defaultEffortOption: effortOptions.first
        )
    }
}
