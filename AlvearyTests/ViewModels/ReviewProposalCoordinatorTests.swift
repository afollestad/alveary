import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// Confirming a review is the one host-tool decision that awaits GitHub, so these cover the
/// ordering that keeps a card from claiming a submission that did not happen.
@MainActor
final class ReviewProposalCoordinatorTests: XCTestCase {
    func testConfirmingSubmitsThePendingDraftAndResolvesTheCard() async throws {
        let fixture = try Fixture()
        fixture.service.detailResult = .success(
            makePullRequestDetail(id: Fixture.identifier, pendingReviewNodeID: "DRAFT_1")
        )

        let didSubmit = await fixture.coordinator.confirm(proposalID: Fixture.proposalID, event: .approve)

        XCTAssertTrue(didSubmit)
        // With a draft on GitHub, submitting finishes *that* review rather than opening a second.
        XCTAssertEqual(
            fixture.service.submittedPendingReviews,
            [.init(reviewNodeID: "DRAFT_1", event: .approve, body: "Looks good to me.")]
        )
        XCTAssertTrue(fixture.service.submittedReviews.isEmpty)
        XCTAssertNil(try fixture.conversation.pullRequestReviewProposal())
        XCTAssertNil(fixture.coordinator.presentation(forProposalID: Fixture.proposalID))
        XCTAssertEqual(fixture.outcomeMarkers().count, 1)
    }

    func testConfirmingWithoutADraftPostsASummaryOnlyReview() async throws {
        let fixture = try Fixture()
        fixture.service.detailResult = .success(makePullRequestDetail(id: Fixture.identifier))
        fixture.service.submitResult = .success(())

        let didSubmit = await fixture.coordinator.confirm(proposalID: Fixture.proposalID, event: .comment)

        XCTAssertTrue(didSubmit)
        XCTAssertEqual(fixture.service.submittedReviews.count, 1)
        XCTAssertTrue(fixture.service.submittedPendingReviews.isEmpty)
    }

    func testTheUserCanSubmitAVerdictOtherThanTheOneProposed() async throws {
        let fixture = try Fixture()
        fixture.service.detailResult = .success(
            makePullRequestDetail(id: Fixture.identifier, pendingReviewNodeID: "DRAFT_1")
        )

        fixture.coordinator.selectEvent(.requestChanges, forProposalID: Fixture.proposalID)
        let selected = fixture.coordinator.selectedEvent(forProposalID: Fixture.proposalID)
        _ = await fixture.coordinator.confirm(proposalID: Fixture.proposalID, event: try XCTUnwrap(selected))

        XCTAssertEqual(fixture.service.submittedPendingReviews.first?.event, .requestChanges)
        // The marker records what was actually submitted, not what the model asked for.
        XCTAssertEqual(
            fixture.outcomeMarkers().first?.content.map { HostToolWidgetOutcomeMarker.title(fromContent: $0) },
            "request_changes"
        )
    }

    func testAFailedSubmissionLeavesTheProposalConfirmableWithItsError() async throws {
        let fixture = try Fixture()
        fixture.service.detailResult = .success(
            makePullRequestDetail(id: Fixture.identifier, pendingReviewNodeID: "DRAFT_1")
        )
        fixture.service.submitPendingReviewResult = .failure(.rateLimited)

        let didSubmit = await fixture.coordinator.confirm(proposalID: Fixture.proposalID, event: .approve)

        XCTAssertFalse(didSubmit)
        // Unresolved, never wrongly resolved: the card must not claim a review was submitted.
        XCTAssertNotNil(try fixture.conversation.pullRequestReviewProposal())
        XCTAssertNotNil(fixture.coordinator.errorMessage(forProposalID: Fixture.proposalID))
        XCTAssertTrue(fixture.outcomeMarkers().isEmpty)
    }

    func testPickingAVerdictNotifiesSoTheCardReRenders() throws {
        let fixture = try Fixture()
        // The transcript re-reads coordinator state only on the change notification, so a
        // silent selection would leave the picker looking stuck on the old verdict.
        let notified = XCTNSNotificationExpectation(
            name: .reviewProposalCardStateChanged,
            object: nil,
            notificationCenter: fixture.notificationCenter
        )

        fixture.coordinator.selectEvent(.comment, forProposalID: Fixture.proposalID)

        wait(for: [notified], timeout: 1)
        XCTAssertEqual(fixture.coordinator.selectedEvent(forProposalID: Fixture.proposalID), .comment)
    }

    func testRejectingClearsTheProposalWithoutTouchingGitHub() async throws {
        let fixture = try Fixture()

        XCTAssertTrue(fixture.coordinator.reject(proposalID: Fixture.proposalID))

        XCTAssertNil(try fixture.conversation.pullRequestReviewProposal())
        XCTAssertEqual(fixture.service.detailCallCount, 0)
        XCTAssertTrue(fixture.service.submittedReviews.isEmpty)
        XCTAssertEqual(fixture.outcomeMarkers().count, 1)
    }

    func testApproveIsUnavailableOnTheViewersOwnPullRequest() async throws {
        let fixture = try Fixture()
        var detail = makePullRequestDetail(id: Fixture.identifier)
        detail.viewerLogin = detail.authorLogin
        detail.reviewThreads = [
            makeReviewThread(nodeID: "THREAD_1", path: "File0.swift", line: 1, isPending: true)
        ]
        fixture.service.detailResult = .success(detail)
        fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))

        fixture.coordinator.ensurePreview(proposalID: Fixture.proposalID)
        try await fixture.waitForPreview()

        XCTAssertFalse(fixture.coordinator.canSubmit(proposalID: Fixture.proposalID, event: .approve))
        XCTAssertTrue(fixture.coordinator.canSubmit(proposalID: Fixture.proposalID, event: .comment))
    }

    func testThePreviewShowsOnlyTheHunksThePendingCommentsSitOn() async throws {
        let fixture = try Fixture()
        var detail = makePullRequestDetail(id: Fixture.identifier)
        detail.reviewThreads = [
            makeReviewThread(nodeID: "THREAD_1", path: "File1.swift", line: 1, isPending: true),
            // A submitted thread is not part of what confirming would publish.
            makeReviewThread(nodeID: "THREAD_2", path: "File2.swift", line: 1, isPending: false)
        ]
        fixture.service.detailResult = .success(detail)
        fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 3))

        fixture.coordinator.ensurePreview(proposalID: Fixture.proposalID)
        try await fixture.waitForPreview()

        guard case .loaded(let preview)? = fixture.coordinator.preview(forProposalID: Fixture.proposalID) else {
            return XCTFail("expected a loaded preview")
        }
        XCTAssertEqual(preview.files.map(\.path), ["File1.swift"])
        XCTAssertEqual(preview.pendingCommentCount, 1)
        XCTAssertEqual(preview.annotations.threads.count, 1)
    }

    func testAFailedPreviewLoadLeavesTheCardConfirmable() async throws {
        let fixture = try Fixture()
        fixture.service.detailResult = .failure(.rateLimited)

        fixture.coordinator.ensurePreview(proposalID: Fixture.proposalID)
        try await fixture.waitForPreview()

        guard case .failed? = fixture.coordinator.preview(forProposalID: Fixture.proposalID) else {
            return XCTFail("expected a failed preview")
        }
        XCTAssertNotNil(fixture.coordinator.presentation(forProposalID: Fixture.proposalID))
    }
}

@MainActor
private final class Fixture {
    static let proposalID = "proposal-1"
    static let identifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)

    let modelContext: ModelContext
    let coordinator: PullRequestReviewProposalCoordinator
    let service = StubPullRequestsService()
    let conversation: Conversation
    let notificationCenter = NotificationCenter()

    init() throws {
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        modelContext = context
        let thread = AgentThread(name: "Thread")
        let sourceConversation = Conversation(id: "source-conversation", provider: "codex", thread: thread)
        conversation = sourceConversation
        thread.conversations = [sourceConversation]
        context.insert(thread)
        try sourceConversation.storePullRequestReviewProposal(
            PullRequestReviewProposalRecord(
                payloadVersion: PullRequestReviewProposalRecord.currentPayloadVersion,
                id: Self.proposalID,
                deduplicationKey: "dedup-1",
                repositoryNameWithOwner: Self.identifier.nameWithOwner,
                number: Self.identifier.number,
                event: "approve",
                body: "Looks good to me.",
                titleSnapshot: "Detail title",
                pendingCommentCountSnapshot: 1,
                sourceProviderID: "codex",
                sourceProcessToken: "token",
                sourceRequestID: "request-1",
                createdAt: Date(timeIntervalSince1970: 1_000)
            )
        )
        try context.save()

        coordinator = PullRequestReviewProposalCoordinator(
            modelContext: context,
            pullRequestsService: service,
            notificationCenter: notificationCenter,
            now: { Date(timeIntervalSince1970: 2_000) }
        )
    }

    func outcomeMarkers() -> [ConversationEventRecord] {
        conversation.events.filter { $0.type == ConversationEventRecord.hostToolOutcomeType }
    }

    /// The preview loads in its own task; poll rather than guessing at a sleep.
    func waitForPreview(timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch coordinator.preview(forProposalID: Self.proposalID) {
            case .loaded, .failed:
                return
            case .loading, nil:
                try await Task.sleep(nanoseconds: 5_000_000)
            }
        }
        XCTFail("the preview never settled")
    }
}
