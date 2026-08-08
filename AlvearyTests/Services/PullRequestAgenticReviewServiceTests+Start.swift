import Foundation
import XCTest

@testable import Alveary

/// What `startReview` answers with, and when. The split it encodes: the caller gets its
/// conversation as soon as the thread exists, and everything that reaches GitHub rides the
/// returned `dispatch` behind that navigation.
@MainActor
extension PullRequestAgenticReviewServiceTests {
    private struct StartFixture {
        let fixture: SidebarTestFixture
        let service: PullRequestAgenticReviewService
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

    private func makeStartFixture() throws -> StartFixture {
        let fixture = try SidebarTestFixture()
        let pullRequests = StubPullRequestsService()
        let identifier = makePullRequestSummary(number: 7, status: .open).id
        pullRequests.detailResult = .success(makePullRequestDetail(id: identifier, status: .open))
        let linkService = PullRequestLinkService(modelContext: fixture.context, service: pullRequests)
        let prompts = RecordedPrompts()
        let service = PullRequestAgenticReviewService(
            lifecycleService: fixture.viewModel.threadLifecycle,
            linkService: linkService,
            settingsService: fixture.settingsService,
            // nil discovery takes the static fallback resolver, so no provider subprocess runs.
            providerDiscovery: nil,
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

        let started = try await start.service.startReview(identifier: start.identifier, url: start.url)

        XCTAssertFalse(started.conversationID.isEmpty)
        XCTAssertTrue(start.prompts.prompts.isEmpty, "The first prompt must not have been dispatched yet")

        gate.open()
        try await started.dispatch.value

        XCTAssertEqual(start.prompts.prompts, [PullRequestAgenticReviewService.reviewRequestPrompt(url: start.url)])
    }

    /// Linking still precedes dispatch — moving both behind navigation must not reorder them, or
    /// transcript detection asks a redundant "link this?" question under the prompt.
    func testTheDeferredHalfLinksBeforeItDispatchesTheFirstPrompt() async throws {
        let start = try makeStartFixture()

        let started = try await start.service.startReview(identifier: start.identifier, url: start.url)
        try await started.dispatch.value

        XCTAssertEqual(start.prompts.wasLinkedAtDispatch, [true])
    }

    /// The pane already fetched this pull request; linking must not fetch it again.
    func testASuppliedDetailSparesTheLinkItsRoundTrip() async throws {
        let start = try makeStartFixture()
        let detail = makePullRequestDetail(id: start.identifier, title: "Handed over", status: .open)

        let started = try await start.service.startReview(
            identifier: start.identifier,
            url: start.url,
            knownDetail: detail
        )
        try await started.dispatch.value

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

        let started = try await start.service.startReview(
            identifier: start.identifier,
            url: start.url,
            knownDetail: mismatched
        )
        try await started.dispatch.value

        XCTAssertEqual(start.pullRequests.detailCallCount, 1)
        let thread = start.fixture.context.resolveConversation(conversationID: started.conversationID)?.thread
        XCTAssertEqual(thread?.linkedPullRequests.first?.id, start.identifier)
        XCTAssertNotEqual(thread?.linkedPullRequests.first?.summary.title, "Wrong pull request")
    }

    /// A GitHub hiccup must not stop a review from starting — the link is best-effort and the
    /// prompt still goes out.
    func testAFailedLinkStillDispatchesTheFirstPrompt() async throws {
        let start = try makeStartFixture()
        start.pullRequests.detailResult = .failure(.transport("offline"))

        let started = try await start.service.startReview(identifier: start.identifier, url: start.url)
        try await started.dispatch.value

        XCTAssertEqual(start.prompts.prompts.count, 1)
        XCTAssertEqual(start.prompts.wasLinkedAtDispatch, [false])
    }
}
