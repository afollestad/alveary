import Foundation
import XCTest

@testable import Alveary

/// A pull request Alveary changes somewhere other than its pane — a review confirmed on the
/// transcript card, or an `alveary_host` mutation — has to reach an open pane, because nothing in
/// `PullRequestDetail` is re-derived locally.
@MainActor
extension PullRequestsViewModelTests {
    // MARK: - Confirming on the transcript card

    /// The bug this covers: the card's Confirm goes straight to the coordinator, so before the
    /// announcement the pane kept rendering its pre-submission reviewers and timeline.
    func testConfirmingOnTheTranscriptCardRefreshesTheOpenPane() async throws {
        let fixture = try ReviewProposalAttachmentFixture()
        await fixture.openPane()
        XCTAssertTrue(try XCTUnwrap(fixture.session?.detail?.reviews).isEmpty)
        fixture.service.detailResult = .success(fixture.reviewedDetail())

        // Exactly the card's call: no `bodyOverride`, and nothing from the pane involved.
        _ = await fixture.coordinator.confirm(proposalID: ReviewProposalAttachmentFixture.proposalID, event: .approve)

        await waitForPullRequestCondition { fixture.session?.detail?.reviews.isEmpty == false }
        XCTAssertEqual(fixture.session?.detail?.reviews.map(\.state), [.approved])
        XCTAssertEqual(fixture.session?.detail?.reviewers.map(\.state), [.approved])
    }

    /// "Pending review" versus "Previously reviewed" comes from the `review-requested:@me` search
    /// bucket, so the list has to refetch too.
    func testConfirmingOnTheTranscriptCardRefreshesTheList() async throws {
        let fixture = try ReviewProposalAttachmentFixture()
        await fixture.openPane()
        XCTAssertEqual(fixture.service.listCallCount, 0)

        _ = await fixture.coordinator.confirm(proposalID: ReviewProposalAttachmentFixture.proposalID, event: .approve)

        await waitForPullRequestCondition {
            // A load is one request per bucket and they land independently, so waiting on the
            // first would let the assertion below race the siblings.
            fixture.service.listCallCount >= fixture.viewModel.selectedFilter.requiredBuckets.count
        }
        // One load, which is one request per bucket the visible tab renders.
        XCTAssertEqual(fixture.service.listCallCount, fixture.viewModel.selectedFilter.requiredBuckets.count)
    }

    /// The card publishes what the model wrote, so a summary typed into the footer was never sent.
    /// Clearing it would drop text the user can still submit as a review of its own.
    func testConfirmingOnTheTranscriptCardKeepsAnUnpublishedFooterSummary() async throws {
        let fixture = try ReviewProposalAttachmentFixture()
        await fixture.openPane()
        fixture.viewModel.updateOverallReviewComment("Typed but never sent")

        _ = await fixture.coordinator.confirm(proposalID: ReviewProposalAttachmentFixture.proposalID, event: .approve)

        await waitForPullRequestCondition {
            fixture.service.listCallCount >= fixture.viewModel.selectedFilter.requiredBuckets.count
        }
        XCTAssertEqual(fixture.session?.pendingReview.overallComment, "Typed but never sent")
        // What was published is the proposal's body, which is what proves the text went nowhere.
        XCTAssertEqual(fixture.service.submittedPendingReviews.map(\.body), ["Some notes."])
    }

    /// The footer's Submit owns its own epilogue — one that also clears the draft it just
    /// published — so the announcement must not stack a second refetch on top of it.
    func testAFooterSubmitRefetchesTheDetailOnlyOnce() async throws {
        let fixture = try ReviewProposalAttachmentFixture()
        await fixture.openPane()
        let before = fixture.service.detailCallCount

        let didSubmit = await fixture.viewModel.submitReview(event: .comment)
        await drainMainQueue()

        XCTAssertTrue(didSubmit)

        // The coordinator's own pre-submit read, plus the footer epilogue's reload. No third.
        XCTAssertEqual(fixture.service.detailCallCount, before + 2)
    }

    // MARK: - Host tool mutations

    /// A reply or a resolved thread changes the timeline but cannot move a list row.
    func testACommentAnnouncementRefreshesThePaneButNotTheList() async throws {
        let fixture = try ReviewProposalAttachmentFixture()
        await fixture.openPane()
        let before = fixture.service.detailCallCount

        fixture.announceChange(affectsListRow: false)

        await waitForPullRequestCondition { fixture.service.detailCallCount > before }
        XCTAssertEqual(fixture.service.detailCallCount, before + 1)
        await drainMainQueue()
        XCTAssertEqual(fixture.service.listCallCount, 0)
    }

    /// A state change moves the row's status glyph and can move its bucket, so both refresh.
    func testAStateChangeAnnouncementRefreshesTheListToo() async throws {
        let fixture = try ReviewProposalAttachmentFixture()
        await fixture.openPane()

        fixture.announceChange(affectsListRow: true)

        await waitForPullRequestCondition {
            fixture.service.listCallCount >= fixture.viewModel.selectedFilter.requiredBuckets.count
        }
        XCTAssertEqual(fixture.service.listCallCount, fixture.viewModel.selectedFilter.requiredBuckets.count)
    }

    /// One agent turn answers and resolves several threads in a row; that is one round trip's
    /// worth of staleness, not five.
    func testABurstOfAnnouncementsCoalescesIntoOneRefetch() async throws {
        let fixture = try ReviewProposalAttachmentFixture()
        await fixture.openPane()
        let before = fixture.service.detailCallCount

        for _ in 0..<4 {
            fixture.announceChange(affectsListRow: true)
        }

        await waitForPullRequestCondition { fixture.service.detailCallCount > before }
        await drainMainQueue()
        XCTAssertEqual(fixture.service.detailCallCount, before + 1)
        // Four announcements still coalesce into one load, not one per announcement.
        XCTAssertEqual(fixture.service.listCallCount, fixture.viewModel.selectedFilter.requiredBuckets.count)
    }

    /// The list screen can be open with no pane beside it.
    func testAnAnnouncementWithNoPaneOpenStillRefreshesTheList() async throws {
        let fixture = try ReviewProposalAttachmentFixture()

        fixture.announceChange(affectsListRow: true)

        await waitForPullRequestCondition {
            fixture.service.listCallCount >= fixture.viewModel.selectedFilter.requiredBuckets.count
        }
        XCTAssertEqual(fixture.service.detailCallCount, 0)
    }

    /// `openPane` deliberately does not refetch a retained session, so the announcement is the
    /// only thing keeping one the user routed away from current.
    func testAnAnnouncementRefreshesARetainedDeactivatedSession() async throws {
        let fixture = try ReviewProposalAttachmentFixture()
        await fixture.openPane()
        fixture.viewModel.deactivatePane()
        fixture.service.detailResult = .success(fixture.reviewedDetail())

        fixture.announceChange(affectsListRow: false)

        await waitForPullRequestCondition { fixture.session?.detail?.reviews.isEmpty == false }
        XCTAssertEqual(fixture.session?.detail?.reviews.map(\.state), [.approved])
    }

    /// Dismissal discards the session, so a debounced refetch waiting on it dies with it.
    func testDismissingThePaneDropsItsPendingRefetch() async throws {
        let fixture = try ReviewProposalAttachmentFixture()
        await fixture.openPane()
        let generation = try XCTUnwrap(fixture.session?.generation)
        let before = fixture.service.detailCallCount

        fixture.announceChange(affectsListRow: false)
        fixture.viewModel.dismissPane(fixture.target, generation: generation, restoreFocus: false)

        await drainMainQueue()
        XCTAssertEqual(fixture.service.detailCallCount, before)
    }

    func testAnAnnouncementForAnotherPullRequestLeavesThePaneAlone() async throws {
        let fixture = try ReviewProposalAttachmentFixture()
        await fixture.openPane()
        let before = fixture.service.detailCallCount

        fixture.announceChange(
            identifier: PullRequestIdentifier(owner: "octo", repo: "alpha", number: 99),
            affectsListRow: false
        )

        await drainMainQueue()
        XCTAssertEqual(fixture.service.detailCallCount, before)
    }

    /// A refresh nobody asked for must not put the Overview's dismissless first-load banner over a
    /// detail that is still perfectly renderable.
    func testAFailedBackgroundRefreshKeepsTheDetailAndShowsNoBanner() async throws {
        let fixture = try ReviewProposalAttachmentFixture()
        await fixture.openPane()
        let loaded = try XCTUnwrap(fixture.session?.detail)
        fixture.service.detailResult = .failure(.rateLimited)
        let before = fixture.service.detailCallCount

        fixture.announceChange(affectsListRow: false)

        await waitForPullRequestCondition { fixture.service.detailCallCount > before }
        await drainMainQueue()
        XCTAssertEqual(fixture.session?.detail, loaded)
        XCTAssertNil(fixture.session?.detailError)
        XCTAssertFalse(try XCTUnwrap(fixture.session?.isLoadingDetail))
    }
}
