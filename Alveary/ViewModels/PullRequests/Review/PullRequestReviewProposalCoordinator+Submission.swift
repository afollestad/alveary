import Foundation

// What confirming a review proposal actually sends to GitHub. Split from the coordinator so its
// file stays inside the length limit; these reach the service through the `service` accessor rather
// than the private stored property, and hold no coordinator state of their own.
extension PullRequestReviewProposalCoordinator {
    /// The confirmed submission. Staged comments are written into the viewer's pending draft
    /// first — adopting an existing draft, since GitHub allows one per viewer, which also keeps
    /// publishing the user's own draft comments the way submitting always has — and
    /// `submitPendingReview` is the one call that publishes anything. A failure before it leaves
    /// only a private draft, and the card stays confirmable for a retry.
    ///
    /// `body` is already resolved by the caller: the pull request pane's footer summary when the
    /// submit came from there, otherwise what the model proposed.
    func submit(
        presentation: PullRequestReviewProposalPresentation,
        event: PullRequestReviewEvent,
        body: String,
        detail: PullRequestDetail
    ) async throws {
        guard !presentation.comments.isEmpty else {
            if let reviewNodeID = detail.pendingReviewNodeID {
                // Finish the existing draft rather than opening a second review beside it.
                try await service.submitPendingReview(
                    reviewNodeID: reviewNodeID,
                    event: event,
                    body: body
                )
            } else {
                try await service.submitReview(presentation.identifier, event: event, body: body)
            }
            return
        }
        let reviewNodeID: String
        if let existing = detail.pendingReviewNodeID {
            reviewNodeID = existing
        } else if let pullRequestNodeID = detail.nodeID {
            reviewNodeID = try await service.createPendingReview(pullRequestNodeID: pullRequestNodeID)
        } else {
            throw PullRequestReviewProposalSubmissionError.missingNodeID
        }
        for comment in presentation.comments where !Self.alreadyWritten(comment, in: detail) {
            _ = try await service.addPendingReviewComment(
                reviewNodeID: reviewNodeID,
                path: comment.path,
                line: comment.line,
                side: comment.side == PullRequestDiffSide.left.rawValue ? .left : .right,
                body: comment.body
            )
        }
        try await service.submitPendingReview(reviewNodeID: reviewNodeID, event: event, body: body)
    }

    /// A retry after a mid-flow failure must not write a comment the first attempt already
    /// landed, so a staged comment matching a pending draft comment by anchor and body is
    /// skipped. This also absorbs a staged comment identical to one the user drafted themselves —
    /// including one the pane composed into the envelope beside an already-drafted duplicate.
    static func alreadyWritten(
        _ comment: PullRequestReviewProposalRecord.Comment,
        in detail: PullRequestDetail
    ) -> Bool {
        let body = comment.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.reviewThreads.contains { thread in
            thread.isPending
                && thread.path == comment.path
                && thread.line == comment.line
                && thread.side.rawValue == comment.side
                && thread.comments.contains { candidate in
                    candidate.isPending
                        && candidate.bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines) == body
                }
        }
    }
}
