import Foundation
import XCTest

@testable import Alveary

/// A staged comment's line can stop resolving after the pull request moves. The card has to say so
/// rather than quietly drawing fewer comments than it counts, and confirming has to refuse before
/// it writes anything.
extension ReviewProposalCoordinatorTests {
    /// The mismatch this fixes: the summary counts every staged comment, so a dropped one made the
    /// card promise more than it drew.
    func testAnUnplaceableCommentIsReportedRatherThanDropped() async throws {
        let fixture = try ReviewProposalFixture(
            comments: [
                ReviewProposalFixture.stagedComment(line: 1, body: "Still fine."),
                ReviewProposalFixture.stagedComment(path: "Gone.swift", line: 40, body: "Vanished.")
            ]
        )
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 2))

        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
        try await fixture.waitForPreview()

        guard case .loaded(let preview)? = fixture.coordinator.preview(
            forProposalID: ReviewProposalFixture.proposalID
        ) else {
            return XCTFail("expected a loaded preview")
        }
        XCTAssertEqual(preview.staleComments.map(\.path), ["Gone.swift"])
        XCTAssertEqual(preview.staleComments.map(\.proposedIndex), [1])
        // The one that still resolves is drawn as before.
        XCTAssertEqual(preview.files.map(\.path), ["File0.swift"])
        XCTAssertEqual(preview.proposedCommentCount, 2)
    }

    func testRemovingAnUnplaceableCommentClearsItFromTheCard() async throws {
        let fixture = try ReviewProposalFixture(
            comments: [
                ReviewProposalFixture.stagedComment(line: 1, body: "Still fine."),
                ReviewProposalFixture.stagedComment(path: "Gone.swift", line: 40, body: "Vanished.")
            ]
        )
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 2))
        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
        try await fixture.waitForPreview()

        XCTAssertTrue(
            fixture.coordinator.removeStagedComment(proposalID: ReviewProposalFixture.proposalID, at: 1)
        )

        guard case .loaded(let preview)? = fixture.coordinator.preview(
            forProposalID: ReviewProposalFixture.proposalID
        ) else {
            return XCTFail("expected a loaded preview")
        }
        XCTAssertTrue(preview.staleComments.isEmpty)
        XCTAssertEqual(preview.proposedCommentCount, 1)
    }

    /// Confirming used to loop `addPendingReviewComment` with no re-check, so a stale anchor failed
    /// partway and left earlier comments in a draft `submitPendingReview` never finished — which no
    /// retry could clear, because the same anchor failed again.
    func testConfirmingRefusesBeforeWritingAnythingWhenAnAnchorIsStale() async throws {
        let fixture = try ReviewProposalFixture(
            comments: [
                ReviewProposalFixture.stagedComment(line: 1, body: "Still fine."),
                ReviewProposalFixture.stagedComment(path: "Gone.swift", line: 40, body: "Vanished.")
            ]
        )
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 2))

        let didSubmit = await fixture.coordinator.confirm(
            proposalID: ReviewProposalFixture.proposalID,
            event: .comment
        )

        XCTAssertFalse(didSubmit)
        // Nothing reached GitHub — not even the draft the good comment would have opened.
        XCTAssertTrue(fixture.service.createdPendingReviewNodeIDs.isEmpty)
        XCTAssertTrue(fixture.service.addedPendingComments.isEmpty)
        XCTAssertTrue(fixture.service.submittedPendingReviews.isEmpty)
        // The proposal survives so the user can remove the stale comment and retry.
        XCTAssertNotNil(fixture.coordinator.presentation(forProposalID: ReviewProposalFixture.proposalID))
        let message = try XCTUnwrap(
            fixture.coordinator.errorMessage(forProposalID: ReviewProposalFixture.proposalID)
        )
        XCTAssertTrue(message.contains("Gone.swift"), message)
    }

    /// The re-check is a safety net, and a net that cannot be fetched must not block a submit that
    /// would otherwise have gone through.
    func testAnUnfetchableDiffStillConfirmsUsingTheStoredLines() async throws {
        let fixture = try ReviewProposalFixture(
            comments: [ReviewProposalFixture.stagedComment(line: 1, body: "Still fine.")]
        )
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        fixture.service.diffResult = .failure(.rateLimited)

        let didSubmit = await fixture.coordinator.confirm(
            proposalID: ReviewProposalFixture.proposalID,
            event: .comment
        )

        XCTAssertTrue(didSubmit)
        XCTAssertEqual(fixture.service.addedPendingComments.map(\.body), ["Still fine."])
    }

    /// The cache entry must hold the hunk a relocated comment *resolved* to. Narrowing by the
    /// stored line would cache whatever hunk now occupies the old number instead, and the next
    /// launch's cached paint would claim the comment cannot be placed until the refresh corrected
    /// it.
    func testTheCacheKeepsTheHunkARelocatedCommentResolvedTo() async throws {
        let staged = DiffParser.parse(
            """
            diff --git a/File0.swift b/File0.swift
            --- a/File0.swift
            +++ b/File0.swift
            @@ -0,0 +1,1 @@
            +gamma()
            """
        )
        let fingerprint = try XCTUnwrap(
            ReviewProposalAnchorResolution.fingerprint(path: "File0.swift", line: 1, side: .right, in: staged)
        )
        let fixture = try ReviewProposalFixture(
            comments: [
                PullRequestReviewProposalRecord.Comment(
                    path: "File0.swift",
                    line: 1,
                    side: "RIGHT",
                    body: "Moved far.",
                    anchorContent: fingerprint.content,
                    anchorContext: fingerprint.context
                )
            ]
        )
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        // The stored line 1 still exists — holding different code in its own hunk — while the
        // commented content moved to line 50, a hunk the stored number cannot reach.
        fixture.service.diffResult = .success(
            """
            diff --git a/File0.swift b/File0.swift
            --- a/File0.swift
            +++ b/File0.swift
            @@ -1,1 +1,1 @@
            -gamma()
            +other()
            @@ -49,0 +50,1 @@
            +gamma()
            """
        )

        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
        try await fixture.waitForCachedEntry()

        let entry = try XCTUnwrap(fixture.cachedEntries()[ReviewProposalFixture.proposalID])
        XCTAssertEqual(entry.files.flatMap(\.hunks).map(\.newStart), [50])
    }

    /// A first attempt lands a relocated comment at its *new* line, so a retry has to dedup by that
    /// line — matching the stored one would re-post the comment on every retry.
    func testARetrySkipsARelocatedCommentTheFirstAttemptAlreadyWrote() async throws {
        let staged = DiffParser.parse(makeUnifiedDiffFixture(fileCount: 1))
        let fingerprint = try XCTUnwrap(
            ReviewProposalAnchorResolution.fingerprint(
                path: "File0.swift",
                line: 1,
                side: .right,
                in: staged
            )
        )
        let fixture = try ReviewProposalFixture(
            comments: [
                PullRequestReviewProposalRecord.Comment(
                    path: "File0.swift",
                    line: 1,
                    side: "RIGHT",
                    body: "Consider a guard here.",
                    anchorContent: fingerprint.content,
                    anchorContext: fingerprint.context
                )
            ]
        )
        var detail = makePullRequestDetail(id: ReviewProposalFixture.identifier, pendingReviewNodeID: "DRAFT_1")
        // The first attempt already wrote the comment — at the relocated line 2, not the stored 1.
        detail.reviewThreads = [
            makeReviewThread(nodeID: "THREAD_1", path: "File0.swift", line: 2, isPending: true)
        ]
        fixture.service.detailResult = .success(detail)
        fixture.service.diffResult = .success(
            """
            diff --git a/File0.swift b/File0.swift
            --- a/File0.swift
            +++ b/File0.swift
            @@ -0,0 +1,2 @@
            +inserted line
            \("+" + fingerprint.content)
            """
        )

        let didSubmit = await fixture.coordinator.confirm(
            proposalID: ReviewProposalFixture.proposalID,
            event: .comment
        )

        XCTAssertTrue(didSubmit)
        XCTAssertTrue(fixture.service.addedPendingComments.isEmpty)
        XCTAssertEqual(fixture.service.submittedPendingReviews.map(\.reviewNodeID), ["DRAFT_1"])
    }

    /// A comment whose code moved publishes where the code went, matching what the card drew.
    func testConfirmingPublishesARelocatedLineRatherThanTheStoredOne() async throws {
        let staged = DiffParser.parse(makeUnifiedDiffFixture(fileCount: 1))
        let fingerprint = try XCTUnwrap(
            ReviewProposalAnchorResolution.fingerprint(
                path: "File0.swift",
                line: 1,
                side: .right,
                in: staged
            )
        )
        let fixture = try ReviewProposalFixture(
            comments: [
                PullRequestReviewProposalRecord.Comment(
                    path: "File0.swift",
                    line: 1,
                    side: "RIGHT",
                    body: "Moved.",
                    anchorContent: fingerprint.content,
                    anchorContext: fingerprint.context
                )
            ]
        )
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        // The same content, pushed down a line by an insertion above it.
        fixture.service.diffResult = .success(
            """
            diff --git a/File0.swift b/File0.swift
            --- a/File0.swift
            +++ b/File0.swift
            @@ -0,0 +1,2 @@
            +inserted line
            \("+" + fingerprint.content)
            """
        )

        let didSubmit = await fixture.coordinator.confirm(
            proposalID: ReviewProposalFixture.proposalID,
            event: .comment
        )

        XCTAssertTrue(didSubmit)
        XCTAssertEqual(fixture.service.addedPendingComments.map(\.line), [2])
    }
}
