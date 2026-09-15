import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// What `start` answers with, and when. The split it encodes: the caller gets its conversation as
/// soon as the thread exists, and everything that reaches GitHub rides the returned `dispatch`
/// behind that navigation.
@MainActor
extension PullRequestAgenticThreadServiceTests {
    struct StartFixture {
        let fixture: SidebarTestFixture
        let service: PullRequestAgenticThreadService
        let pullRequests: StubPullRequestsService
        let prompts: RecordedPrompts
        let identifier: PullRequestIdentifier
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "https://github.com/octo/alpha/pull/7")!
    }

    /// The dispatch runs on its own task, so what it did has to be recorded rather than returned.
    final class RecordedPrompts: @unchecked Sendable {
        private(set) var prompts: [String] = []
        /// Whether the link had already landed when the prompt was dispatched.
        private(set) var wasLinkedAtDispatch: [Bool] = []

        func record(prompt: String, wasLinked: Bool) {
            prompts.append(prompt)
            wasLinkedAtDispatch.append(wasLinked)
        }
    }

    /// `existingDirectories` stands in for the filesystem the workspace ladder probes, so a rung
    /// can be made to find or miss a checkout without one being on disk. `branchesByRoot` is the
    /// same stand-in for git: it answers the probe that decides whether a borrow is actually on the
    /// pull request's head branch, and an unlisted root reads as unreadable.
    func makeStartFixture(
        fixture: SidebarTestFixture? = nil,
        existingDirectories: Set<String> = [],
        branchesByRoot: [String: String] = [:],
        harnessDiscovery: (any AgentHarnessDiscoveryService)? = nil
    ) throws -> StartFixture {
        let fixture = try fixture ?? SidebarTestFixture()
        let pullRequests = StubPullRequestsService()
        let identifier = makePullRequestSummary(number: 7, status: .open).id
        pullRequests.detailResult = .success(makePullRequestDetail(id: identifier, status: .open))
        let linkService = PullRequestLinkService(modelContext: fixture.context, service: pullRequests)
        let prompts = RecordedPrompts()
        let service = PullRequestAgenticThreadService(
            lifecycleService: fixture.viewModel.threadLifecycle,
            linkService: linkService,
            pullRequestsService: pullRequests,
            settingsService: fixture.settingsService,
            worktreeManager: fixture.worktreeManager,
            taskWorkspaceOwnershipService: fixture.taskWorkspaceOwnershipService,
            // Tests use either static defaults or an injected catalog, never a live harness.
            harnessDiscovery: harnessDiscovery,
            directoryExists: { existingDirectories.contains($0) },
            currentBranch: { branchesByRoot[$0] },
            startInitialPrompt: { conversation, prompt in
                let isLinked = conversation.thread?.linkedPullRequests.isEmpty == false
                prompts.record(prompt: prompt, wasLinked: isLinked)
            }
        )
        return StartFixture(
            fixture: fixture,
            service: service,
            pullRequests: pullRequests,
            prompts: prompts,
            identifier: identifier
        )
    }

    /// The regression this pins: linking used to sit in front of the return, so the sidebar
    /// selection waited on a `gh api graphql` round trip.
    func testStartAnswersBeforeTheLinkResolves() async throws {
        let start = try makeStartFixture()
        let gate = PullRequestsServiceGate()
        start.pullRequests.detailGate = gate

        let started = try await start.service.start(kind: .review, identifier: start.identifier, url: start.url)

        XCTAssertFalse(started.conversationID.isEmpty)
        XCTAssertTrue(start.prompts.prompts.isEmpty, "The first prompt must not have been dispatched yet")

        gate.open()
        _ = try await started.dispatch.value

        XCTAssertEqual(start.prompts.prompts, [PullRequestAgenticThreadService.Kind.review.requestPrompt(url: start.url)])
    }

    /// Linking still precedes dispatch — moving both behind navigation must not reorder them, or
    /// transcript detection asks a redundant "link this?" question under the prompt.
    func testTheDeferredHalfLinksBeforeItDispatchesTheFirstPrompt() async throws {
        let start = try makeStartFixture()

        let started = try await start.service.start(kind: .review, identifier: start.identifier, url: start.url)
        _ = try await started.dispatch.value

        XCTAssertEqual(start.prompts.wasLinkedAtDispatch, [true])
    }

    func testEachRouteCreatesThreadsWithItsOwnAgentSettings() async throws {
        let start = try makeStartFixture(harnessDiscovery: RecordingHarnessDiscoveryService(statuses: [
            .claude: SettingsViewModelTests.harnessStatus(for: .claude, modelOptions: AgentModelOptionTestFixtures.claudeModelOptions),
            .codex: SettingsViewModelTests.harnessStatus(for: .codex, modelOptions: AgentModelOptionTestFixtures.codexModelOptions)
        ]))
        let project = Project(
            path: "/tmp/alveary-permission-project",
            name: "alpha",
            githubRepository: start.identifier.nameWithOwner
        )
        start.fixture.context.insert(project)
        try start.fixture.context.save()
        start.fixture.settingsService.update { settings in
            settings.permissionMode = "acceptEdits"
            settings.pullRequestReviewHarness = "codex"
            settings.pullRequestReviewModel = "gpt-5.4-mini"
            settings.pullRequestReviewEffort = "medium"
            settings.pullRequestReviewPermissionMode = "never"
            settings.pullRequestAddressFeedbackHarness = "claude"
            settings.pullRequestAddressFeedbackModel = "haiku"
            settings.pullRequestAddressFeedbackEffort = "low"
            settings.pullRequestAddressFeedbackPermissionMode = "bypassPermissions"
        }

        for kind in PullRequestAgenticThreadService.Kind.allCases {
            let started = try await start.service.start(kind: kind, identifier: start.identifier, url: start.url)
            _ = try await started.dispatch.value

            let conversation = start.fixture.context.resolveConversation(conversationID: started.conversationID)
            let thread = conversation?.thread
            let settings = start.fixture.settingsService.current
            let expected = kind == .review ? settings.pullRequestReviewAgent : settings.pullRequestAddressFeedbackAgent
            XCTAssertEqual(conversation?.harness, expected.harness)
            XCTAssertEqual(thread?.model, expected.model)
            XCTAssertEqual(thread?.effort, expected.effort)
            XCTAssertEqual(thread?.permissionMode, expected.permissionMode)
        }
    }

    /// The pane already fetched this pull request; linking must not fetch it again.
    func testASuppliedDetailSparesTheLinkItsRoundTrip() async throws {
        let start = try makeStartFixture()
        let detail = makePullRequestDetail(id: start.identifier, title: "Handed over", status: .open)

        let started = try await start.service.start(
            kind: .review,
            identifier: start.identifier,
            url: start.url,
            knownDetail: detail
        )
        _ = try await started.dispatch.value

        XCTAssertEqual(start.pullRequests.detailCallCount, 0)
        let thread = start.fixture.context.resolveConversation(conversationID: started.conversationID)?.thread
        XCTAssertEqual(thread?.linkedPullRequests.first?.summary.title, "Handed over")
    }

    /// A detail naming a different pull request proves nothing about this one, so the link falls
    /// back to fetching rather than storing a snapshot of the wrong thing.
    func testADetailForAnotherPullRequestIsIgnoredAndTheLinkStillFetches() async throws {
        let start = try makeStartFixture()
        let otherIdentifier = makePullRequestSummary(number: 8, status: .open).id
        let mismatched = makePullRequestDetail(id: otherIdentifier, title: "Wrong pull request", status: .open)

        let started = try await start.service.start(
            kind: .review,
            identifier: start.identifier,
            url: start.url,
            knownDetail: mismatched
        )
        _ = try await started.dispatch.value

        XCTAssertEqual(start.pullRequests.detailCallCount, 1)
        let thread = start.fixture.context.resolveConversation(conversationID: started.conversationID)?.thread
        XCTAssertEqual(thread?.linkedPullRequests.first?.id, start.identifier)
        XCTAssertNotEqual(thread?.linkedPullRequests.first?.summary.title, "Wrong pull request")
    }

    /// A pane opened from a list row has a summary before it has a detail, and that is enough to
    /// store the link — which is what makes linking reliable rather than merely attempted.
    func testASuppliedSummarySparesTheLinkItsRoundTrip() async throws {
        let start = try makeStartFixture()
        let summary = makePullRequestSummary(number: start.identifier.number, status: .open)

        let started = try await start.service.start(
            kind: .review,
            identifier: start.identifier,
            url: start.url,
            knownSummary: summary
        )
        _ = try await started.dispatch.value

        XCTAssertEqual(start.pullRequests.detailCallCount, 0)
        let thread = start.fixture.context.resolveConversation(conversationID: started.conversationID)?.thread
        XCTAssertEqual(thread?.linkedPullRequests.first?.id, start.identifier)
    }

    /// A GitHub hiccup must not stop a review from starting — the link is best-effort and the
    /// prompt still goes out.
    func testAFailedLinkStillDispatchesTheFirstPrompt() async throws {
        let start = try makeStartFixture()
        start.pullRequests.detailResult = .failure(.transport("offline"))

        let started = try await start.service.start(kind: .review, identifier: start.identifier, url: start.url)
        _ = try await started.dispatch.value

        XCTAssertEqual(start.prompts.prompts.count, 1)
        XCTAssertEqual(start.prompts.wasLinkedAtDispatch, [false])
    }

    /// Reported rather than swallowed: the caller toasts it. It must not *throw*, because a throw
    /// means the prompt never went out and would end a run that is in fact working.
    func testAFailedLinkIsReportedInTheDispatchOutcome() async throws {
        let start = try makeStartFixture()
        start.pullRequests.detailResult = .failure(.transport("offline"))

        let started = try await start.service.start(kind: .review, identifier: start.identifier, url: start.url)
        let outcome = try await started.dispatch.value

        XCTAssertNotNil(outcome.linkFailure)
        XCTAssertEqual(start.prompts.prompts.count, 1)
    }

    /// The ordinary path reports nothing, so the caller has no toast to show.
    func testASuccessfulLinkReportsNoFailure() async throws {
        let start = try makeStartFixture()

        let started = try await start.service.start(
            kind: .review,
            identifier: start.identifier,
            url: start.url,
            knownDetail: makePullRequestDetail(id: start.identifier, status: .open)
        )
        let outcome = try await started.dispatch.value

        XCTAssertNil(outcome.linkFailure)
    }
    func testConcurrentCallersSharePreparationAndCheckpointTheirOwnDestination() async throws {
        let entered = expectation(description: "harness discovery entered")
        let discovery = LaunchGatedDiscovery(onRead: { entered.fulfill() })
        defer { discovery.gate.open() }
        let start = try makeStartFixture(harnessDiscovery: discovery)
        var checkpoints: [PullRequestAgenticThreadDestination] = []
        let first = Task { try await start.service.start(
            kind: .review, identifier: start.identifier, url: start.url,
            checkpoint: { checkpoints.append($0); XCTAssertTrue(start.prompts.prompts.isEmpty) }
        ) }
        await fulfillment(of: [entered], timeout: 2)
        let joining = expectation(description: "second caller entered")
        var didJoin = false
        let uppercase = PullRequestIdentifier(owner: "OCTO", repo: "ALPHA", number: start.identifier.number)
        let second = Task { try await start.service.start(
            kind: .review, identifier: uppercase, url: start.url,
            validateSource: { if !didJoin { didJoin = true; joining.fulfill() } },
            checkpoint: { checkpoints.append($0) }
        ) }
        await fulfillment(of: [joining], timeout: 2)
        discovery.gate.open()

        let created = try await first.value
        let existing = try await second.value
        _ = try await created.dispatch.value

        XCTAssertEqual(existing.conversationID, created.conversationID)
        XCTAssertEqual(checkpoints.map(\.disposition), [.created, .existing])
        XCTAssertEqual(try start.fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 1)
        XCTAssertEqual(start.prompts.prompts.count, 1)
        XCTAssertNotNil(start.service.dispatch(conversationID: created.conversationID))
    }

    func testSourceIsRevalidatedAfterPreparationBeforeInsertingATask() async throws {
        let entered = expectation(description: "harness discovery entered")
        let discovery = LaunchGatedDiscovery(onRead: { entered.fulfill() })
        defer { discovery.gate.open() }
        let start = try makeStartFixture(harnessDiscovery: discovery)
        var sourceExists = true
        let launch = Task { try await start.service.start(
            kind: .review, identifier: start.identifier, url: start.url,
            validateSource: { if !sourceExists { throw LaunchTestError.refused } }
        ) }
        await fulfillment(of: [entered], timeout: 2)
        sourceExists = false
        discovery.gate.open()

        do {
            _ = try await launch.value
            XCTFail("A missing caller must not create a task")
        } catch { XCTAssertEqual(error as? LaunchTestError, .refused) }
        XCTAssertEqual(try start.fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 0)
        XCTAssertFalse(start.service.activity.isWorking(start.identifier, kind: .review))
    }

    func testCancellationDuringPreparationCreatesNoTask() async throws {
        let entered = expectation(description: "harness discovery entered")
        let discovery = LaunchGatedDiscovery(onRead: { entered.fulfill() })
        defer { discovery.gate.open() }
        let start = try makeStartFixture(harnessDiscovery: discovery)
        let launch = Task { try await start.service.start(kind: .review, identifier: start.identifier, url: start.url) }
        await fulfillment(of: [entered], timeout: 2)
        launch.cancel()
        discovery.gate.open()

        do {
            _ = try await launch.value
            XCTFail("Cancelled preparation must not create a task")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try start.fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 0)
        XCTAssertTrue(start.prompts.prompts.isEmpty)
    }

    func testCheckpointFailureRetainsTheTaskAndNeverDispatches() async throws {
        let start = try makeStartFixture()
        var destination: PullRequestAgenticThreadDestination?
        do {
            _ = try await start.service.start(
                kind: .review, identifier: start.identifier, url: start.url,
                checkpoint: { destination = $0; throw LaunchTestError.refused }
            )
            XCTFail("A failed checkpoint must prevent dispatch")
        } catch {
            let failure = try XCTUnwrap(error as? PullRequestAgenticThreadLaunchError)
            XCTAssertEqual(failure.destination, destination)
            XCTAssertEqual(failure.underlying as? LaunchTestError, .refused)
        }
        let target = try XCTUnwrap(destination)
        let conversation = try XCTUnwrap(start.fixture.context.resolveConversation(conversationID: target.conversationID))
        XCTAssertEqual(conversation.events.filter { $0.type == ConversationEventRecord.errorType }.count, 1)
        XCTAssertTrue(start.prompts.prompts.isEmpty)
        XCTAssertFalse(start.service.activity.isWorking(start.identifier, kind: .review))
    }

    func testAnActiveRouteReusesItsTaskUntilTheHarnessTurnEnds() async throws {
        let start = try makeStartFixture()
        let first = try await start.service.start(kind: .review, identifier: start.identifier, url: start.url)
        _ = try await first.dispatch.value
        let existing = try await start.service.start(kind: .review, identifier: start.identifier, url: start.url)
        XCTAssertEqual(existing.destination.disposition, .existing)
        XCTAssertEqual(existing.conversationID, first.conversationID)
        for signal in [ActivitySignal.busy, .idle] {
            NotificationCenter.default.post(name: .agentStatusChanged, object: nil, userInfo: [
                AgentStatusChangedKey.conversationID: first.conversationID, AgentStatusChangedKey.signal: signal
            ])
        }
        let next = try await start.service.start(kind: .review, identifier: start.identifier, url: start.url)
        _ = try await next.dispatch.value
        XCTAssertNotEqual(next.conversationID, first.conversationID)
        XCTAssertEqual(start.prompts.prompts.count, 2)
    }
}

private enum LaunchTestError: Error, Equatable {
    case refused
}

private actor LaunchGatedDiscovery: AgentHarnessDiscoveryService {
    nonisolated let gate = PullRequestsServiceGate()
    private let onRead: @Sendable () -> Void
    private let statuses: [AgentHarnessID: AgentHarnessStatus] = [
        .claude: AgentHarnessStatus(harnessId: .claude, installation: .installed, setup: .ready,
                                    modelOptions: AgentModelOptionTestFixtures.claudeModelOptions)
    ]

    init(onRead: @escaping @Sendable () -> Void) { self.onRead = onRead }

    func harnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] {
        onRead()
        await gate.wait()
        return statuses
    }

    func installedHarnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] { statuses }
    func availableHarnessStatuses(projectURL: URL?) async -> [AgentHarnessID: AgentHarnessStatus] { statuses }
    func modelOptions(for harnessId: AgentHarnessID) async -> [AgentModelOption] { statuses[harnessId]?.modelOptions ?? [] }
    func stableHarnessOrdering() async -> [AgentHarnessID] { [.claude] }
}
