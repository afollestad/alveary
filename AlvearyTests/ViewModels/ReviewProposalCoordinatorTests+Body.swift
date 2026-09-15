import Foundation
import Observation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ReviewProposalCoordinatorTests {
    func testSavingTheBodyPersistsWithoutRefreshingTheDiffOrRegrouping() throws {
        let fixture = try ReviewProposalFixture(comments: [ReviewProposalFixture.stagedComment(body: "Inline")])
        let before = try XCTUnwrap(fixture.conversation.pullRequestReviewProposal())
        let recorder = fixture.cardStateRecorder()
        let preview = fixture.coordinator.preview(forProposalID: before.id)
        let body = "First paragraph with `code`.\n\nSecond paragraph."

        XCTAssertTrue(fixture.coordinator.updateBody(proposalID: before.id, body: body))
        fixture.coordinator.reload()

        XCTAssertEqual(fixture.coordinator.presentation(forProposalID: before.id)?.body, body)
        let stored = try XCTUnwrap(fixture.conversation.pullRequestReviewProposal())
        XCTAssertEqual(stored.replacingBody(before.body ?? ""), before)
        XCTAssertEqual(fixture.coordinator.preview(forProposalID: before.id), preview)
        XCTAssertEqual(recorder.count, 1)
        XCTAssertTrue(fixture.outcomeMarkers().isEmpty)
        XCTAssertTrue(fixture.service.submittedReviews.isEmpty)
    }

    func testClearingTheBodySubmitsThreadsWithoutRestoringTheOriginal() async throws {
        let fixture = try ReviewProposalFixture(comments: [ReviewProposalFixture.stagedComment(body: "Inline")])
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier, pendingReviewNodeID: "DRAFT_1"))
        let id = ReviewProposalFixture.proposalID

        XCTAssertTrue(fixture.coordinator.updateBody(proposalID: id, body: " \n "))
        fixture.coordinator.reload()
        XCTAssertNil(fixture.coordinator.presentation(forProposalID: id)?.body)
        XCTAssertFalse(fixture.coordinator.canSubmit(proposalID: id, event: .requestChanges))
        let submitted = await fixture.coordinator.confirm(proposalID: id, event: .comment)

        XCTAssertTrue(submitted)
        XCTAssertEqual(fixture.service.submittedPendingReviews.map(\.body), [""])
        XCTAssertEqual(fixture.service.addedPendingComments.map(\.body), ["Inline"])
        let outcome = try XCTUnwrap(fixture.outcomeMarkers().first?.content)
        XCTAssertEqual(HostToolWidgetOutcomeMarker.body(fromContent: outcome), "")
    }

    func testClearedRequestChangesIsRefusedBeforeSubmission() async throws {
        let fixture = try ReviewProposalFixture()
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        let id = ReviewProposalFixture.proposalID
        XCTAssertTrue(fixture.coordinator.updateBody(proposalID: id, body: ""))
        let submitted = await fixture.coordinator.confirm(proposalID: id, event: .requestChanges)
        XCTAssertFalse(submitted)
        XCTAssertEqual(
            fixture.coordinator.errorMessage(forProposalID: id),
            "This review needs a top-level comment or a different review action."
        )
        XCTAssertTrue(fixture.service.submittedPendingReviews.isEmpty)
        XCTAssertTrue(fixture.service.submittedReviews.isEmpty)
    }

    func testFailedSubmissionRetainsTheEditedBodyForRetry() async throws {
        let fixture = try ReviewProposalFixture()
        let id = ReviewProposalFixture.proposalID
        XCTAssertTrue(fixture.coordinator.updateBody(proposalID: id, body: "Edited\n\nComment"))
        fixture.service.detailResult = .failure(.rateLimited)
        let failed = await fixture.coordinator.confirm(proposalID: id, event: .approve)
        XCTAssertFalse(failed)
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier, pendingReviewNodeID: "DRAFT_1"))
        let submitted = await fixture.coordinator.confirm(proposalID: id, event: .approve)
        XCTAssertTrue(submitted)
        XCTAssertEqual(fixture.service.submittedPendingReviews.map(\.body), ["Edited\n\nComment"])
        XCTAssertEqual(HostToolWidgetOutcomeMarker.body(fromContent: try XCTUnwrap(fixture.outcomeMarkers().first?.content)), "Edited\n\nComment")
    }

    func testConfirmationReadsTheSavedBodyAndRefusesSupersededProposals() async throws {
        let fixture = try ReviewProposalFixture()
        let id = ReviewProposalFixture.proposalID
        let record = try XCTUnwrap(fixture.conversation.pullRequestReviewProposal())
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier, pendingReviewNodeID: "DRAFT_1"))
        try fixture.conversation.storePullRequestReviewProposal(record.replacingBody("Saved elsewhere"))
        try fixture.modelContext.save()
        let submitted = await fixture.coordinator.confirm(proposalID: id, event: .approve)
        XCTAssertTrue(submitted)
        XCTAssertEqual(fixture.service.submittedPendingReviews.map(\.body), ["Saved elsewhere"])

        let stale = try ReviewProposalFixture()
        stale.conversation.clearPullRequestReviewProposal()
        try stale.modelContext.save()
        let staleSubmitted = await stale.coordinator.confirm(proposalID: id, event: .approve)
        XCTAssertFalse(staleSubmitted)
        XCTAssertTrue(stale.service.submittedPendingReviews.isEmpty)
        XCTAssertTrue(stale.service.submittedReviews.isEmpty)
    }

    func testBodyEditsRefuseMissingAndSubmittingProposals() throws {
        let fixture = try ReviewProposalFixture()
        let id = ReviewProposalFixture.proposalID
        let original = try fixture.conversation.pullRequestReviewProposal()
        fixture.coordinator.beginSubmitting(id, conversationID: fixture.conversation.id)
        XCTAssertFalse(fixture.coordinator.updateBody(proposalID: id, body: "Too late"))
        fixture.coordinator.endSubmitting(id, conversationID: fixture.conversation.id)
        XCTAssertEqual(try fixture.conversation.pullRequestReviewProposal(), original)

        fixture.conversation.clearPullRequestReviewProposal()
        try fixture.modelContext.save()
        XCTAssertFalse(fixture.coordinator.updateBody(proposalID: id, body: "Stale"))
        XCTAssertNotNil(fixture.coordinator.errorMessage(forProposalID: id))
    }

    func testBodySavesRefreshOtherWindowContextsWithoutRefreshingPreviewsOrRegrouping() async throws {
        let fixture = try ReviewProposalFixture(secondProposal: true)
        let other = PullRequestReviewProposalCoordinator(
            modelContext: ModelContext(fixture.modelContext.container), pullRequestsService: fixture.service,
            notificationCenter: fixture.notificationCenter
        )
        let id = ReviewProposalFixture.proposalID
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        other.ensurePreview(proposalID: id)
        try await fixture.wait(until: {
            if case .loaded? = other.preview(forProposalID: id) { return true }
            return false
        }, "preview missing")
        let preview = other.preview(forProposalID: id)
        let unrelated = other.presentation(forProposalID: ReviewProposalFixture.secondProposalID)
        let lifecycle = ReviewProposalCardStateRecorder(notificationCenter: fixture.notificationCenter, name: .pullRequestReviewProposalsChanged)
        other.selectEvent(.requestChanges, forProposalID: id)
        let detailCalls = fixture.service.detailCallCount

        for body in ["Saved in another window\n\nSecond paragraph", ""] {
            XCTAssertTrue(fixture.coordinator.updateBody(proposalID: id, body: body))
            try await fixture.wait(until: { other.presentation(forProposalID: id)?.body == (body.isEmpty ? nil : body) }, "saved body missing")
            XCTAssertEqual(other.preview(forProposalID: id), preview)
            XCTAssertEqual(other.presentation(forProposalID: ReviewProposalFixture.secondProposalID), unrelated)
            XCTAssertEqual(other.selectedEvent(forProposalID: id), .requestChanges)
        }
        XCTAssertEqual(lifecycle.count, 0)
        XCTAssertEqual(fixture.service.detailCallCount, detailCalls)
        other.reload()
        XCTAssertNil(other.presentation(forProposalID: id)?.body)
    }

    func testStaleWindowDismissalRecordsTheSavedBodyAndRefusesSubmissionInAnotherWindow() throws {
        for body in ["Edited elsewhere", ""] {
            let fixture = try ReviewProposalFixture()
            let other = PullRequestReviewProposalCoordinator(
                modelContext: ModelContext(fixture.modelContext.container), pullRequestsService: fixture.service,
                notificationCenter: fixture.notificationCenter
            )
            let id = ReviewProposalFixture.proposalID
            XCTAssertTrue(fixture.coordinator.updateBody(proposalID: id, body: body))
            fixture.coordinator.beginSubmitting(id, conversationID: fixture.conversation.id)
            XCTAssertTrue(other.isSubmitting(proposalID: id))
            XCTAssertFalse(other.reject(proposalID: id))
            XCTAssertFalse(other.updateBody(proposalID: id, body: "Too late"))
            fixture.coordinator.endSubmitting(id, conversationID: fixture.conversation.id)
            XCTAssertTrue(other.reject(proposalID: id))
            let reader = ModelContext(fixture.modelContext.container)
            let records = try reader.fetch(FetchDescriptor<ConversationEventRecord>())
            let marker = try XCTUnwrap(records.first { $0.type == ConversationEventRecord.hostToolOutcomeType }?.content)
            XCTAssertEqual(HostToolWidgetOutcomeMarker.body(fromContent: marker), body)
        }
    }

    func testDismissalRefusesAnAlreadyClearedProposalWithoutWritingAnotherOutcome() throws {
        let fixture = try ReviewProposalFixture()
        fixture.conversation.clearPullRequestReviewProposal()
        try fixture.modelContext.save()
        XCTAssertFalse(fixture.coordinator.reject(proposalID: ReviewProposalFixture.proposalID))
        XCTAssertTrue(fixture.outcomeMarkers().isEmpty)
    }

    func testEmptyCommentSubmissionValidatesFreshPendingThreads() async throws {
        for hasPendingThread in [true, false] {
            let fixture = try ReviewProposalFixture(body: nil, pendingCommentCount: hasPendingThread ? 0 : 1)
            let threads = hasPendingThread ? [makeReviewThread(nodeID: "THREAD", path: "File0.swift", line: nil, isPending: true)] : []
            fixture.service.detailResult = .success(makePullRequestDetail(
                id: ReviewProposalFixture.identifier, reviewThreads: threads, pendingReviewNodeID: "DRAFT"
            ))
            fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
            fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
            try await fixture.waitForPreview()
            XCTAssertEqual(fixture.coordinator.canSubmit(proposalID: ReviewProposalFixture.proposalID, event: .comment), hasPendingThread)
            let submitted = await fixture.coordinator.confirm(proposalID: ReviewProposalFixture.proposalID, event: .comment)
            XCTAssertEqual(submitted, hasPendingThread)
            XCTAssertEqual(fixture.service.submittedPendingReviews.map(\.body), hasPendingThread ? [""] : [])
        }
    }

    func testTwoWindowsCanRestoreAnEarlierBodyWithoutLosingTheWrite() throws {
        let fixture = try ReviewProposalFixture()
        let other = PullRequestReviewProposalCoordinator(
            modelContext: ModelContext(fixture.modelContext.container), pullRequestsService: fixture.service,
            notificationCenter: fixture.notificationCenter
        )
        let id = ReviewProposalFixture.proposalID
        for (coordinator, body) in [(fixture.coordinator, "A"), (other, "B"), (fixture.coordinator, "A"), (other, "")] {
            XCTAssertTrue(coordinator.updateBody(proposalID: id, body: body))
            let reader = ModelContext(fixture.modelContext.container)
            let saved = try reader.resolveConversation(conversationID: fixture.conversation.id)?.pullRequestReviewProposal()
            XCTAssertEqual(saved?.body, body.isEmpty ? nil : body)
        }
        XCTAssertTrue(fixture.coordinator.reject(proposalID: id))
        let reader = ModelContext(fixture.modelContext.container)
        XCTAssertNil(try reader.resolveConversation(conversationID: fixture.conversation.id)?.pullRequestReviewProposal())
    }

    func testOtherWindowSubmissionChangesInvalidateThePaneObservation() async throws {
        let fixture = try ReviewProposalFixture()
        let other = PullRequestReviewProposalCoordinator(
            modelContext: ModelContext(fixture.modelContext.container), pullRequestsService: fixture.service,
            notificationCenter: fixture.notificationCenter
        )
        let id = ReviewProposalFixture.proposalID
        let began = expectation(description: "other window observed submission")
        withObservationTracking {
            XCTAssertFalse(other.isSubmitting(proposalID: id))
        } onChange: { began.fulfill() }
        fixture.coordinator.beginSubmitting(id, conversationID: fixture.conversation.id)
        fixture.coordinator.notifyChanged()
        await fulfillment(of: [began], timeout: 2)
        XCTAssertTrue(other.isSubmitting(proposalID: id))
        let ended = expectation(description: "other window observed completion")
        withObservationTracking {
            _ = other.isSubmitting(proposalID: id)
        } onChange: { ended.fulfill() }
        fixture.coordinator.endSubmitting(id, conversationID: fixture.conversation.id)
        fixture.coordinator.notifyChanged()
        await fulfillment(of: [ended], timeout: 2)
        XCTAssertFalse(other.isSubmitting(proposalID: id))
    }

    func testWindowCreatedDuringSubmissionObservesCompletion() async throws {
        let fixture = try ReviewProposalFixture()
        let id = ReviewProposalFixture.proposalID
        fixture.coordinator.beginSubmitting(id, conversationID: fixture.conversation.id)
        let other = PullRequestReviewProposalCoordinator(
            modelContext: ModelContext(fixture.modelContext.container), pullRequestsService: fixture.service,
            notificationCenter: fixture.notificationCenter
        )
        let ended = expectation(description: "new window observed completion")
        withObservationTracking {
            XCTAssertTrue(other.isSubmitting(proposalID: id))
        } onChange: { ended.fulfill() }
        fixture.coordinator.endSubmitting(id, conversationID: fixture.conversation.id)
        fixture.coordinator.notifyChanged()
        await fulfillment(of: [ended], timeout: 2)
        XCTAssertFalse(other.isSubmitting(proposalID: id))
    }

}
