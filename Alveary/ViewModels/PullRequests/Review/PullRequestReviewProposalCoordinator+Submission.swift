import Foundation

// What confirming a review proposal actually sends to GitHub. Split from the coordinator so its
// file stays inside the length limit; these reach the service through the `service` accessor rather
// than the private stored property, and hold no coordinator state of their own.
extension PullRequestReviewProposalCoordinator {
    /// Opens the submitting span, in both places that track it.
    ///
    /// `submittingConversationIDsByProposalID` is what the card and the sidebar's working ring
    /// read; the announcement is what thread archive and delete read, because that guard's owner is
    /// app-scoped while this coordinator is per-window — `PullRequestReviewSubmissionActivity` owns
    /// why. Paired with `endSubmitting` so the two can never drift: a span left open on one side
    /// would either freeze a card or wedge a thread as permanently unarchivable.
    func beginSubmitting(_ proposalID: String, conversationID: String) {
        submittingConversationIDsByProposalID[proposalID] = conversationID
        PullRequestReviewSubmissionActivity.post(
            conversationID: conversationID,
            isSubmitting: true,
            on: notificationCenter
        )
    }

    /// Closes what `beginSubmitting` opened. Called from `confirm`'s `defer`, so it runs on the
    /// failure path too.
    func endSubmitting(_ proposalID: String, conversationID: String) {
        submittingConversationIDsByProposalID[proposalID] = nil
        PullRequestReviewSubmissionActivity.post(
            conversationID: conversationID,
            isSubmitting: false,
            on: notificationCenter
        )
    }

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
        // Anchors are validated at propose time and can go stale afterwards, so they are resolved
        // once more here — before anything is created. GitHub refuses an anchor that no longer
        // exists, and the writes below are a loop: a mid-loop refusal used to leave earlier
        // comments in a private draft that `submitPendingReview` never finished, which no retry
        // could clear because the same anchor failed again.
        //
        // Best-effort on purpose. This is a safety net, and a net that cannot be fetched must not
        // block a submit that would otherwise have gone through: an unfetchable diff falls back to
        // publishing the stored lines, which is exactly what confirming did before it existed.
        let lines = await resolvedCommentLines(for: presentation)
        let stale = zip(presentation.comments, lines).filter { $0.1 == nil }.map(\.0)
        guard stale.isEmpty else {
            throw PullRequestReviewProposalSubmissionError.staleAnchors(paths: stale.map(\.path))
        }
        let reviewNodeID: String
        if let existing = detail.pendingReviewNodeID {
            reviewNodeID = existing
        } else if let pullRequestNodeID = detail.nodeID {
            reviewNodeID = try await service.createPendingReview(pullRequestNodeID: pullRequestNodeID)
        } else {
            throw PullRequestReviewProposalSubmissionError.missingNodeID
        }
        for (comment, line) in zip(presentation.comments, lines)
        where !Self.alreadyWritten(comment, at: line ?? comment.line, in: detail) {
            _ = try await service.addPendingReviewComment(
                reviewNodeID: reviewNodeID,
                path: comment.path,
                // The resolved line, not the stored one: a relocated comment must publish where its
                // code moved to, matching what the card drew.
                line: line ?? comment.line,
                side: comment.side == PullRequestDiffSide.left.rawValue ? .left : .right,
                body: comment.body
            )
        }
        try await service.submitPendingReview(reviewNodeID: reviewNodeID, event: event, body: body)
    }

    /// Where each staged comment should publish, or nil for one the diff cannot place.
    ///
    /// A failed diff fetch yields the stored lines rather than propagating: see `submit`.
    private func resolvedCommentLines(
        for presentation: PullRequestReviewProposalPresentation
    ) async -> [Int?] {
        guard let diffText = try? await service.fetchDiff(presentation.identifier) else {
            return presentation.comments.map { $0.line }
        }
        return ReviewProposalAnchorResolution.resolvedLines(
            presentation.comments,
            against: DiffParser.parse(diffText)
        )
    }

    /// A retry after a mid-flow failure must not write a comment the first attempt already
    /// landed, so a staged comment matching a pending draft comment by anchor and body is
    /// skipped. This also absorbs a staged comment identical to one the user drafted themselves —
    /// including one the pane composed into the envelope beside an already-drafted duplicate.
    ///
    /// `line` is the *resolved* line, because that is where the write loop publishes: a relocated
    /// comment a first attempt landed sits in the draft at its new line, and matching the stored
    /// one would re-post it on every retry.
    static func alreadyWritten(
        _ comment: PullRequestReviewProposalRecord.Comment,
        at line: Int,
        in detail: PullRequestDetail
    ) -> Bool {
        let body = comment.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.reviewThreads.contains { thread in
            thread.isPending
                && thread.path == comment.path
                && thread.line == line
                && thread.side.rawValue == comment.side
                && thread.comments.contains { candidate in
                    candidate.isPending
                        && candidate.bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines) == body
                }
        }
    }
}
