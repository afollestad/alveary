import Foundation
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
        branchesByRoot: [String: String] = [:]
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
            // nil discovery takes the static fallback resolver, so no provider subprocess runs.
            providerDiscovery: nil,
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
}
