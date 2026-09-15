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

    @Test(arguments: [AgentHarnessID.codex, .claude], ReviewDefaultAvailabilityFault.allCases)
    func `unavailable harnesses are omitted instead of replaced`(
        harnessID: AgentHarnessID,
        fault: ReviewDefaultAvailabilityFault
    ) async {
        var settings = AppSettings()
        if fault == .disabledInSettings {
            settings.setHarness(harnessID.rawValue, enabled: false)
        }
        var statuses = ReviewTeamDefaultsFixtures.statuses
        statuses[harnessID] = fault == .absent ? nil : ReviewTeamDefaultsFixtures.status(for: harnessID, fault: fault)
        let (viewModel, _) = await makeViewModel(settings: settings, statuses: statuses)

        let draft = viewModel.reviewTeamEditorSettings()
        let expected = harnessID == .codex
            ? ["claude/claude-opus-5/high", "claude/claude-fable-5-1/max"]
            : ["codex/gpt-5.6-sol/high", "codex/gpt-6-astra/max"]

        #expect(lineup(draft) == expected)
        #expect(viewModel.pullRequestReviewTeamSettingsStatus(peers: draft.pullRequestReviewPeers, settings: draft) == .ready)
    }

    @Test(arguments: [false, true])
    func `unresolvable Sol falls back to Opus without replacing peers`(unsupportedEffort: Bool) async {
        var options = ReviewTeamDefaultsFixtures.models(for: .codex).filter { $0.model != "gpt-5.6-sol" }
        if unsupportedEffort {
            options.append(ReviewTeamDefaultsFixtures.model(harnessID: .codex, id: "gpt-5.6-sol", efforts: ["medium"]))
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
        let statuses: [AgentHarnessID: AgentHarnessStatus] = [
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

    @Test(arguments: [AgentHarnessID.codex, .claude], [false, true])
    func `unavailable peer models or efforts remain requested`(harnessID: AgentHarnessID, unsupportedEffort: Bool) async {
        let modelID = harnessID == .codex ? "gpt-6-astra" : "claude-fable-5-1"
        var options = ReviewTeamDefaultsFixtures.models(for: harnessID).filter { $0.model != modelID }
        if unsupportedEffort {
            options.append(ReviewTeamDefaultsFixtures.model(harnessID: harnessID, id: modelID, efforts: ["high"]))
        }
        var statuses = ReviewTeamDefaultsFixtures.statuses
        statuses[harnessID] = ReviewTeamDefaultsFixtures.status(for: harnessID, models: options)
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
        settings.pullRequestReviewHarness = "codex"
        settings.pullRequestReviewModel = "retired-lead"
        settings.pullRequestReviewEffort = "ultra"
        settings.pullRequestReviewPeers = [
            PullRequestReviewPeer(id: "saved-peer", harnessID: "claude", model: "retired-peer", effort: "high")
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
        statuses: [AgentHarnessID: AgentHarnessStatus] = ReviewTeamDefaultsFixtures.statuses
    ) async -> (SettingsViewModel, InMemorySettingsService) {
        var settings = settings
        settings.pullRequestReviewMode = .reviewTeam
        let service = InMemorySettingsService(current: settings)
        let viewModel = SettingsViewModel(
            settingsService: service,
            harnessDiscovery: RecordingHarnessDiscoveryService(statuses: statuses)
        )
        await viewModel.refreshHarnessStatuses()
        return (viewModel, service)
    }

    private func lineup(_ settings: AppSettings) -> [String] {
        let lead = "\(settings.pullRequestReviewHarness ?? "")/\(settings.pullRequestReviewModel ?? "")/\(settings.pullRequestReviewEffort ?? "")"
        return [lead] + settings.pullRequestReviewPeers.map { "\($0.harnessID)/\($0.model)/\($0.effort)" }
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
    static var statuses: [AgentHarnessID: AgentHarnessStatus] {
        [.codex: status(for: .codex), .claude: status(for: .claude)]
    }

    static func status(
        for harnessID: AgentHarnessID,
        models: [AgentModelOption]? = nil,
        fault: ReviewDefaultAvailabilityFault? = nil
    ) -> AgentHarnessStatus {
        AgentHarnessStatus(
            harnessId: harnessID,
            definition: harnessID == .codex ? CodexHarnessDefinition.definition : ClaudeHarnessDefinition.definition,
            installation: fault == .missingInstallation ? .missing : .installed,
            availability: AgentHarnessAvailability(
                harnessId: harnessID,
                executablePath: fault == .missingExecutable ? nil : fault == .blankExecutable ? " \n" : "/usr/local/bin/\(harnessID.rawValue)"
            ),
            isEnabled: fault != .disabledInDiscovery,
            setup: fault == .needsSetup ? .needsSetup : .ready,
            modelOptions: models ?? self.models(for: harnessID)
        )
    }

    static func models(for harnessID: AgentHarnessID) -> [AgentModelOption] {
        let ids = harnessID == .codex ? ["gpt-5.6-sol", "gpt-6-astra"] : ["claude-opus-5", "claude-fable-5-1"]
        return ids.map { model(harnessID: harnessID, id: $0) }
    }

    static func model(harnessID: AgentHarnessID, id: String, efforts: [String] = ["high", "max"]) -> AgentModelOption {
        let effortOptions = efforts.map {
            AgentHarnessOption(value: $0, label: $0.capitalized, description: "Use \($0) reasoning effort.")
        }
        let label = switch id {
        case "gpt-5.6-sol": "GPT-5.6-Sol"
        case "gpt-6-astra": "GPT-6-Astra"
        case "claude-opus-5": "Opus 5"
        case "claude-fable-5-1": "Fable 5.1"
        default: id
        }
        return AgentModelOption(
            harnessId: harnessID,
            id: id,
            model: id,
            label: label,
            supportedEffortOptions: effortOptions,
            defaultEffortOption: effortOptions.first
        )
    }
}
