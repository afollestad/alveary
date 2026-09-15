import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension PullRequestsViewModelTests {
    func testEnablingAReviewHarnessRefreshesItsCachedDisabledStatus() async {
        let settings = makeReviewTeamHarnessSettings()
        settings.update { $0.setHarness("codex", enabled: false) }
        let discovery = ReviewTeamEnablementDiscovery(settings: settings)
        let cache = CachingAgentHarnessDiscoveryService(base: discovery)
        let resolver = PullRequestReviewTeamResolver(harnessDiscovery: cache)
        await cache.warm()
        let pane = await openedReviewPane(
            settingsService: settings,
            reviewTeamSettingsValidator: { settings in _ = try await resolver.resolve(settings: settings) },
            refreshReviewTeamHarnessDiscovery: { await cache.refresh() }
        )
        await waitFor { pane.viewModel.reviewTeamValidationTask == nil }
        let disabledStatus = await cache.harnessStatuses(projectURL: nil)
        XCTAssertFalse(disabledStatus[.codex]?.isEnabled == true)
        let expectedFailure = PullRequestReviewTeamResolutionError.harnessUnavailable(
            memberID: "peer", memberName: "Reviewer 2", harnessID: "codex"
        )
        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .invalid(expectedFailure.localizedDescription))
        let callsBeforeEnable = discovery.calls

        settings.update { $0.setHarness("codex", enabled: true) }

        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .validating)
        await waitFor { pane.session?.pullRequestReviewTeamValidationStatus == .valid }
        let enabledStatus = await cache.harnessStatuses(projectURL: nil)
        XCTAssertEqual(discovery.calls, callsBeforeEnable + 1)
        XCTAssertTrue(enabledStatus[.codex]?.isEnabled == true)
        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .valid)
    }

    func testReplacedRetryDoesNotRefreshDiscoveryBeforeItsFirstTurn() async {
        let settings = makeReviewTeamHarnessSettings()
        var refreshCalls = 0
        var validatedModels: [String?] = []
        let pane = await openedReviewPane(
            settingsService: settings,
            reviewTeamSettingsValidator: { validatedModels.append($0.pullRequestReviewModel) },
            refreshReviewTeamHarnessDiscovery: { refreshCalls += 1 }
        )
        await waitFor { pane.session?.pullRequestReviewTeamValidationStatus == .valid }
        XCTAssertEqual(validatedModels.count, 1)

        pane.viewModel.retryReviewTeamValidation()
        let replaced = pane.viewModel.reviewTeamValidationTask
        // Both mutations happen without yielding, so the cancelled Retry has not begun discovery yet.
        settings.update { $0.pullRequestReviewModel = "replacement-model" }
        let replacement = pane.viewModel.reviewTeamValidationTask
        await waitFor { pane.session?.pullRequestReviewTeamValidationStatus == .valid }
        await replaced?.value
        await replacement?.value

        XCTAssertEqual(refreshCalls, 0)
        XCTAssertEqual(validatedModels, [nil, "replacement-model"])
        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .valid)
    }

    func testReplacingAnEnablementCheckPreservesItsPendingDiscoveryRefresh() async {
        let settings = makeReviewTeamHarnessSettings()
        settings.update { $0.setHarness("codex", enabled: false) }
        let discovery = ReviewTeamEnablementDiscovery(settings: settings)
        let cache = CachingAgentHarnessDiscoveryService(base: discovery)
        let resolver = PullRequestReviewTeamResolver(harnessDiscovery: cache)
        await cache.warm()
        let pane = await openedReviewPane(
            settingsService: settings,
            reviewTeamSettingsValidator: { settings in _ = try await resolver.resolve(settings: settings) },
            refreshReviewTeamHarnessDiscovery: { await cache.refresh() }
        )
        await waitFor { pane.viewModel.reviewTeamValidationTask == nil }
        let callsBeforeEnable = discovery.calls

        settings.update { $0.setHarness("codex", enabled: true) }
        let replaced = pane.viewModel.reviewTeamValidationTask
        settings.update { $0.pullRequestReviewModel = "sonnet" }
        let replacement = pane.viewModel.reviewTeamValidationTask
        await waitFor { pane.session?.pullRequestReviewTeamValidationStatus == .valid }
        await replaced?.value
        await replacement?.value

        XCTAssertEqual(discovery.calls, callsBeforeEnable + 1)
        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .valid)
    }

    func testEnablementChangesInSingleAgentModeRefreshWhenTeamModeReturns() async {
        let settings = makeReviewTeamHarnessSettings()
        settings.update {
            $0.pullRequestReviewMode = .singleAgent
            $0.setHarness("codex", enabled: false)
        }
        let discovery = ReviewTeamEnablementDiscovery(settings: settings)
        let cache = CachingAgentHarnessDiscoveryService(base: discovery)
        let resolver = PullRequestReviewTeamResolver(harnessDiscovery: cache)
        await cache.warm()
        let pane = await openedReviewPane(
            settingsService: settings,
            reviewTeamSettingsValidator: { settings in _ = try await resolver.resolve(settings: settings) },
            refreshReviewTeamHarnessDiscovery: { await cache.refresh() }
        )

        settings.update { $0.setHarness("codex", enabled: true) }
        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .notRequired)
        XCTAssertNil(pane.viewModel.reviewTeamValidationTask)
        XCTAssertEqual(discovery.calls, 1)

        settings.update { $0.pullRequestReviewMode = .reviewTeam }
        await waitFor { pane.session?.pullRequestReviewTeamValidationStatus == .valid }
        XCTAssertEqual(discovery.calls, 2)

        // A completed refresh consumes the pending enablement change; later model edits reuse its catalog.
        settings.update { $0.pullRequestReviewModel = "sonnet" }
        await waitFor { pane.session?.pullRequestReviewTeamValidationStatus == .valid }
        XCTAssertEqual(discovery.calls, 2)
        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .valid)
    }

    func testSupersededDiscoveryCompletionCannotConsumePendingEnablementRefresh() async {
        let settings = makeReviewTeamHarnessSettings()
        let gates = (0..<3).map { _ in PullRequestsServiceGate() }
        defer { gates.forEach { $0.open() } }
        var refreshCalls = 0
        var validationCalls = 0
        let pane = await openedReviewPane(
            settingsService: settings,
            reviewTeamSettingsValidator: { _ in validationCalls += 1 },
            refreshReviewTeamHarnessDiscovery: {
                let index = refreshCalls
                refreshCalls += 1
                guard gates.indices.contains(index) else { return XCTFail("Unexpected extra refresh") }
                await gates[index].wait()
            }
        )
        await waitFor { pane.session?.pullRequestReviewTeamValidationStatus == .valid }

        settings.update { $0.setHarness("codex", enabled: false) }
        let original = pane.viewModel.reviewTeamValidationTask
        await waitFor { refreshCalls == 1 }
        settings.update { $0.pullRequestReviewModel = "sonnet" }
        let replacement = pane.viewModel.reviewTeamValidationTask
        await waitFor { refreshCalls == 2 }

        gates[0].open()
        await original?.value
        // A third attempt must still refresh: neither of its predecessors completed current discovery.
        settings.update { $0.pullRequestReviewEffort = "high" }
        let current = pane.viewModel.reviewTeamValidationTask
        await waitFor { refreshCalls == 3 }

        gates.forEach { $0.open() }
        await replacement?.value
        await current?.value
        XCTAssertEqual(refreshCalls, 3)
        XCTAssertEqual(validationCalls, 2)
        XCTAssertEqual(pane.session?.pullRequestReviewTeamValidationStatus, .valid)
    }

    private func makeReviewTeamHarnessSettings() -> InMemorySettingsService {
        let settings = InMemorySettingsService()
        settings.update {
            $0.pullRequestReviewMode = .reviewTeam
            $0.defaultHarness = "claude"
            $0.defaultModel = "sonnet"
            $0.effort = "high"
            $0.pullRequestReviewPeers = [
                PullRequestReviewPeer(id: "peer", harnessID: "codex", model: "gpt-5.5", effort: "medium")
            ]
        }
        return settings
    }
}

/// The real cache freezes enablement in each returned status, just as SDK discovery does.
@MainActor
private final class ReviewTeamEnablementDiscovery: AgentHarnessDiscoveryService {
    let settings: InMemorySettingsService
    private(set) var calls = 0

    init(settings: InMemorySettingsService) {
        self.settings = settings
    }

    func harnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] {
        calls += 1
        return Dictionary(uniqueKeysWithValues: [AgentHarnessID.claude, .codex].map { harnessID in
            (
                harnessID,
                AgentHarnessStatus(
                    harnessId: harnessID,
                    definition: harnessID == .claude ? ClaudeHarnessDefinition.definition : CodexHarnessDefinition.definition,
                    installation: .installed,
                    availability: AgentHarnessAvailability(
                        harnessId: harnessID, executablePath: "/usr/local/bin/\(harnessID.rawValue)"
                    ),
                    isEnabled: settings.current.isHarnessEnabled(harnessID.rawValue),
                    setup: .ready,
                    modelOptions: harnessID == .claude
                        ? AgentModelOptionTestFixtures.claudeModelOptions
                        : AgentModelOptionTestFixtures.codexModelOptions
                )
            )
        })
    }

    func installedHarnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] { [:] }
    func availableHarnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] { [:] }
    func modelOptions(for harnessId: AgentHarnessID) async -> [AgentModelOption] { [] }
    func stableHarnessOrdering() async -> [AgentHarnessID] { [.claude, .codex] }
}
