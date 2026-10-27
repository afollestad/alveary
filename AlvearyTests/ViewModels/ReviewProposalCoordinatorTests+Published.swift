import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// A submitted card's comments are real GitHub comments, so every action re-reads GitHub before it
/// writes, and what the read proves lands on the card even when the write is refused.
@MainActor
extension ReviewProposalCoordinatorTests {
    func testConfirmingRecordsThePublishedCommentsOnTheMarker() async throws {
        let evidence = PullRequestReviewProposalRecord.CommentEvidence(findingID: "f1", sourceCandidateIDs: [], priority: 1, votes: [])
        let fixture = try ReviewProposalFixture(comments: [
            PullRequestReviewProposalRecord.Comment(path: "File0.swift", line: 1, side: "RIGHT", body: "First", evidence: evidence),
            ReviewProposalFixture.stagedComment(line: 2, body: "Second")
        ])
        var detail = makePullRequestDetail(id: ReviewProposalFixture.identifier, pendingReviewNodeID: "DRAFT_1")
        detail.reviewThreads = [makeReviewThread(nodeID: "DRAFT", path: "File1.swift", line: 3, isPending: true, bodies: ["Drafted"])]
        fixture.service.detailResult = .success(detail)
        fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 2, addedLinesPerFile: 3))

        let didSubmit = await fixture.coordinator.confirm(proposalID: ReviewProposalFixture.proposalID, event: .comment)

        XCTAssertTrue(didSubmit)
        let published = try XCTUnwrap(markerSnapshot(fixture))
        // The adopted draft publishes with the review, ahead of the comments written for it.
        XCTAssertEqual(published.comments.map(\.nodeID), ["COMMENT_DRAFT_0", "PENDING_COMMENT_First", "PENDING_COMMENT_Second"])
        XCTAssertEqual(published.comments.map(\.evidence), [nil, evidence, nil])
        // The draft's file too, though no staged comment sits on it, so the card can draw that comment.
        XCTAssertEqual(published.files.map(\.path), ["File0.swift", "File1.swift"])
        XCTAssertEqual(fixture.coordinator.publishedReview(forProposalID: ReviewProposalFixture.proposalID), published)
    }

    func testASummaryOnlyReviewRecordsNoSnapshot() async throws {
        let fixture = try ReviewProposalFixture()
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        fixture.service.submitResult = .success(())

        _ = await fixture.coordinator.confirm(proposalID: ReviewProposalFixture.proposalID, event: .comment)

        XCTAssertEqual(fixture.outcomeMarkers().count, 1)
        XCTAssertNil(markerSnapshot(fixture))
        XCTAssertNil(fixture.coordinator.publishedReview(forProposalID: ReviewProposalFixture.proposalID))
    }

    /// Every window's coordinator rewrites markers through its own context, so one window's change must
    /// survive another's later rewrite of the same marker.
    func testAMarkerRewriteKeepsAnotherWindowsEarlierChange() throws {
        let fixture = try ReviewProposalFixture()
        PullRequestReviewProposalOutcomeRecorder.record(
            proposalID: Self.submittedID, sourceConversationID: fixture.conversation.id, outcome: .confirmed, submittedEvent: "comment",
            body: "", published: .fixture(comments: [.fixture(), .fixture(nodeID: "PRRC_2", line: 2)]), in: fixture.modelContext
        )
        let otherWindow = ModelContext(fixture.modelContext.container)
        _ = try otherWindow.fetch(FetchDescriptor<ConversationEventRecord>())

        PullRequestReviewProposalOutcomeRecorder.apply(.init(commentNodeID: "PRRC_1", kind: .deleted), in: fixture.modelContext)
        PullRequestReviewProposalOutcomeRecorder.apply(.init(commentNodeID: "PRRC_2", kind: .edited("Tighter.")), in: otherWindow)

        let stored = try ModelContext(fixture.modelContext.container).fetch(FetchDescriptor<ConversationEventRecord>())
            .compactMap(\.content).compactMap(HostToolWidgetOutcomeMarker.published(fromContent:)).first
        XCTAssertEqual(stored?.comments.map(\.isDeleted), [true, false])
        XCTAssertEqual(stored?.comments.last?.bodyMarkdown, "Tighter.")
    }

    /// A fork shows the same submitted card, but only the conversation that wrote the review may change it.
    func testASubmittedCardActsOnlyInTheConversationThatWroteIt() throws {
        let fixture = try publishedFixture()
        func allowsActions(in conversationID: String) -> Bool? {
            ChatTranscriptView.reviewProposalState(
                proposalID: Self.submittedID, published: .fixture(), conversationID: conversationID, coordinator: fixture.coordinator
            )?.published?.allowsActions
        }

        XCTAssertEqual(allowsActions(in: "source-conversation"), true)
        XCTAssertEqual(allowsActions(in: "fork-conversation"), false)
    }

    func testEditingAPublishedCommentWritesThroughItsFreshRESTIDAndReachesEveryCard() async throws {
        let fixture = try publishedFixture()
        let otherWindow = PullRequestReviewProposalCoordinator(
            modelContext: fixture.modelContext, pullRequestsService: fixture.service,
            notificationCenter: fixture.notificationCenter, remoteReloadDelay: .zero
        )
        _ = otherWindow.publishedReview(forProposalID: Self.submittedID, registering: .fixture())
        fixture.service.detailResult = .success(Self.detail(with: Self.githubComment(databaseId: 77)))
        fixture.service.updateCommentResult = .success(())
        let announcements = fixture.recordAnnouncements()

        let didEdit = await fixture.coordinator.editPublishedComment(proposalID: Self.submittedID, nodeID: "PRRC_1", body: "Tighter.")

        XCTAssertTrue(didEdit)
        XCTAssertEqual(fixture.service.updatedComments.map(\.commentID), [77])
        XCTAssertEqual(fixture.coordinator.publishedReview(forProposalID: Self.submittedID)?.comments.first?.bodyMarkdown, "Tighter.")
        XCTAssertEqual(markerSnapshot(fixture)?.comments.first?.bodyMarkdown, "Tighter.")
        // An open pane refetches, and the list row stays put.
        XCTAssertEqual(announcements.announcements.map(\.affectsListRow), [false])
        XCTAssertTrue(fixture.coordinator.busyPublishedCommentIDs.isEmpty)
        try await fixture.wait(
            until: { otherWindow.publishedReview(forProposalID: Self.submittedID)?.comments.first?.bodyMarkdown == "Tighter." },
            "the other window's card never heard about the edit"
        )
    }

    func testDeletingAPublishedCommentRemovesItFromTheCard() async throws {
        let fixture = try publishedFixture()
        fixture.service.detailResult = .success(Self.detail(with: Self.githubComment(databaseId: 77)))
        fixture.service.deleteCommentResult = .success(())

        let didDelete = await fixture.coordinator.deletePublishedComment(proposalID: Self.submittedID, nodeID: "PRRC_1")

        XCTAssertTrue(didDelete)
        XCTAssertEqual(fixture.service.deletedCommentIDs, [77])
        XCTAssertEqual(fixture.coordinator.publishedReview(forProposalID: Self.submittedID)?.liveComments, [])
        XCTAssertEqual(markerSnapshot(fixture)?.liveComments, [])
    }

    /// Absence proves deletion only when GitHub returned every thread and every comment in them.
    func testACommentGoneFromGitHubIsDroppedWithoutAWrite() async throws {
        let fixture = try publishedFixture()
        fixture.service.detailResult = .success(Self.detail(with: nil))

        let didEdit = await fixture.coordinator.editPublishedComment(proposalID: Self.submittedID, nodeID: "PRRC_1", body: "Tighter.")

        XCTAssertFalse(didEdit)
        XCTAssertTrue(fixture.service.updatedComments.isEmpty)
        XCTAssertEqual(fixture.coordinator.publishedReview(forProposalID: Self.submittedID)?.liveComments, [])
        XCTAssertEqual(fixture.coordinator.publishedErrorMessage(forProposalID: Self.submittedID), "This comment was already deleted on GitHub.")

        // Deleting what is already gone succeeds quietly: what the user asked for is true.
        let deleting = try publishedFixture()
        deleting.service.detailResult = .success(Self.detail(with: nil))
        let didDelete = await deleting.coordinator.deletePublishedComment(proposalID: Self.submittedID, nodeID: "PRRC_1")
        XCTAssertTrue(didDelete)
        XCTAssertTrue(deleting.service.deletedCommentIDs.isEmpty)
        XCTAssertNil(deleting.coordinator.publishedErrorMessage(forProposalID: Self.submittedID))
    }

    /// Any partial thread counts, because a push since the review may have moved the comment's line, and so
    /// does a full page of threads, which may stop short of the comment's.
    func testACommentPastATruncatedPageIsLeftAlone() async throws {
        let partialThread = [makeReviewThread(nodeID: "THREAD", path: "File0.swift", line: 9, isPending: false, totalCommentCount: 40)]
        let fullPage = (0..<PullRequestDetail.reviewThreadPageSize).map {
            makeReviewThread(nodeID: "THREAD_\($0)", path: "File0.swift", line: 9, isPending: false)
        }
        for threads in [partialThread, fullPage] {
            let fixture = try publishedFixture()
            fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier, reviewThreads: threads))

            let didDelete = await fixture.coordinator.deletePublishedComment(proposalID: Self.submittedID, nodeID: "PRRC_1")

            XCTAssertFalse(didDelete)
            XCTAssertTrue(fixture.service.deletedCommentIDs.isEmpty)
            XCTAssertEqual(fixture.coordinator.publishedReview(forProposalID: Self.submittedID)?.liveComments.count, 1)
            XCTAssertNotNil(fixture.coordinator.publishedErrorMessage(forProposalID: Self.submittedID))
        }
    }

    func testAWithdrawnPermissionRefusesAndHidesTheAction() async throws {
        let fixture = try publishedFixture()
        fixture.service.detailResult = .success(Self.detail(with: Self.githubComment(canUpdate: false)))

        let didEdit = await fixture.coordinator.editPublishedComment(proposalID: Self.submittedID, nodeID: "PRRC_1", body: "Tighter.")

        XCTAssertFalse(didEdit)
        XCTAssertTrue(fixture.service.updatedComments.isEmpty)
        let comment = try XCTUnwrap(fixture.coordinator.publishedReview(forProposalID: Self.submittedID)?.comments.first)
        XCTAssertFalse(comment.viewerCanUpdate)
        XCTAssertTrue(comment.viewerCanDelete)
        XCTAssertEqual(fixture.coordinator.publishedErrorMessage(forProposalID: Self.submittedID), "GitHub no longer lets you edit this comment.")
    }

    /// An edit must not overwrite text someone else changed since the card last read it.
    func testAnEditOfTextChangedOnGitHubShowsTheNewTextInstead() async throws {
        let fixture = try publishedFixture()
        fixture.service.detailResult = .success(Self.detail(with: Self.githubComment(body: "Edited on github.com")))

        let didEdit = await fixture.coordinator.editPublishedComment(proposalID: Self.submittedID, nodeID: "PRRC_1", body: "Tighter.")

        XCTAssertFalse(didEdit)
        XCTAssertTrue(fixture.service.updatedComments.isEmpty)
        XCTAssertEqual(
            fixture.coordinator.publishedReview(forProposalID: Self.submittedID)?.comments.first?.bodyMarkdown, "Edited on github.com"
        )
    }

    func testAFailedWriteKeepsTheSnapshot() async throws {
        let fixture = try publishedFixture()
        fixture.service.detailResult = .success(Self.detail(with: Self.githubComment()))
        fixture.service.updateCommentResult = .failure(.rateLimited)

        let didEdit = await fixture.coordinator.editPublishedComment(proposalID: Self.submittedID, nodeID: "PRRC_1", body: "Tighter.")

        XCTAssertFalse(didEdit)
        XCTAssertEqual(fixture.coordinator.publishedReview(forProposalID: Self.submittedID), .fixture())
        XCTAssertEqual(markerSnapshot(fixture), .fixture())
        XCTAssertNotNil(fixture.coordinator.publishedErrorMessage(forProposalID: Self.submittedID))
        XCTAssertTrue(fixture.coordinator.busyPublishedCommentIDs.isEmpty)
    }
}

@MainActor
extension PullRequestPublishedReview {
    static func fixture(
        identifier: PullRequestIdentifier = ReviewProposalFixture.identifier,
        sourceConversationID: String = "source-conversation",
        comments: [Comment] = [.fixture()]
    ) -> Self {
        PullRequestPublishedReview(
            identifier: identifier, sourceConversationID: sourceConversationID, files: [],
            viewerLogin: "viewer", viewerAvatarURL: nil, reviewers: [], comments: comments
        )
    }
}

extension PullRequestPublishedReview.Comment {
    static func fixture(
        nodeID: String = "PRRC_1",
        path: String = "File0.swift",
        line: Int = 1,
        body: String = "Consider a guard here.",
        canUpdate: Bool = true,
        canDelete: Bool = true
    ) -> Self {
        Self(
            nodeID: nodeID, path: path, line: line, side: "RIGHT", bodyMarkdown: body, evidence: nil,
            viewerCanUpdate: canUpdate, viewerCanDelete: canDelete
        )
    }
}

private extension ReviewProposalCoordinatorTests {
    static let submittedID = "submitted-proposal"

    /// A submitted card on screen, its marker in the store, and the coordinator holding its snapshot.
    func publishedFixture() throws -> ReviewProposalFixture {
        let fixture = try ReviewProposalFixture()
        PullRequestReviewProposalOutcomeRecorder.record(
            proposalID: Self.submittedID, sourceConversationID: fixture.conversation.id, outcome: .confirmed,
            submittedEvent: "comment", body: "", published: .fixture(), in: fixture.modelContext
        )
        _ = fixture.coordinator.publishedReview(forProposalID: Self.submittedID, registering: .fixture())
        return fixture
    }

    func markerSnapshot(_ fixture: ReviewProposalFixture) -> PullRequestPublishedReview? {
        fixture.outcomeMarkers().compactMap(\.content).compactMap(HostToolWidgetOutcomeMarker.published(fromContent:)).first
    }

    static func githubComment(
        body: String = "Consider a guard here.",
        databaseId: Int = 4_242,
        canUpdate: Bool = true
    ) -> PullRequestComment {
        PullRequestComment(
            authorLogin: "viewer", authorAvatarURL: nil, bodyMarkdown: body, createdAt: nil,
            databaseId: databaseId, nodeID: "PRRC_1", viewerCanUpdate: canUpdate, viewerCanDelete: true
        )
    }

    /// GitHub's whole answer: one fully fetched thread on the comment's line, or none.
    static func detail(with comment: PullRequestComment?) -> PullRequestDetail {
        makePullRequestDetail(
            id: ReviewProposalFixture.identifier,
            reviewThreads: comment.map { comment in
                [PullRequestReviewThread(
                    path: "File0.swift", line: 1, side: .right, isResolved: false, isOutdated: false, comments: [comment]
                )]
            } ?? []
        )
    }
}
