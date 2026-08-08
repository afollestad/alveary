import Foundation

// The pending review proposal a pane renders staged comments from, plus the one-shot scroll that
// reveals one of them.
//
// The proposal follows the *pull request*, not the route that opened the pane: a proposal names a
// pull request, so opening that pull request from the transcript card, the toolbar, the links
// popover, or the list all show the same staged comments badged "Proposed". Only the scroll is
// particular to a jump. Nothing here reaches GitHub — a staged comment lives in the envelope until
// the review is submitted.
extension PullRequestsViewModel {
    /// Asks the Changes tab to scroll to a comment. Also the Overview's "Show in Changes" entry
    /// point, which reveals an ordinary review thread.
    func requestCommentScroll(to anchor: DiffCommentAnchor, target: PullRequestPaneTarget? = nil) {
        guard let target = target ?? activePaneTarget, paneSessions[target] != nil else {
            return
        }
        mutateSession(target) { session in
            session.pendingCommentScrollTarget = PullRequestPaneCommentScrollTarget(
                token: UUID(),
                anchor: anchor
            )
        }
        // The row only exists once its file is inside the paging window and expanded.
        revealDiffFile(containing: anchor, target: target)
    }

    /// Clears the scroll request the consumer just performed. Matching on the token is what keeps
    /// a late consumer from swallowing a newer request.
    func consumeCommentScrollTarget(token: UUID, target: PullRequestPaneTarget? = nil) {
        guard let target = target ?? activePaneTarget,
              paneSessions[target]?.pendingCommentScrollTarget?.token == token else {
            return
        }
        mutateSession(target) { session in
            session.pendingCommentScrollTarget = nil
        }
    }

    /// The pending review proposal for this pane's pull request, whose staged comments the Changes
    /// tab renders badged "Proposed".
    ///
    /// Keyed by pull request rather than by anything the pane stores, which is what makes every
    /// route agree: a pane opened from the toolbar shows exactly what one opened by jumping from
    /// the proposal's card does. Resolved through the coordinator on every read, so confirming or
    /// rejecting anywhere drops the comments here immediately — no observer to keep in sync, and no
    /// window where the pane would offer to publish a review that no longer exists.
    ///
    /// Two conversations may each hold a proposal for one pull request; the newest wins, so the
    /// choice is deterministic rather than dictionary order.
    func pendingReviewProposal(for target: PullRequestPaneTarget) -> PullRequestReviewProposalPresentation? {
        reviewProposalCoordinator?.presentations.values
            .filter { $0.identifier == target.identifier }
            .max { $0.createdAt < $1.createdAt }
    }

    var activePendingReviewProposal: PullRequestReviewProposalPresentation? {
        activePaneTarget.flatMap { pendingReviewProposal(for: $0) }
    }

    /// Drops one staged comment from the review, by its position in the stored envelope.
    ///
    /// Local by construction — a staged comment exists nowhere on GitHub — so this rewrites the
    /// envelope and reaches no network, which is why it needs no confirmation dialog. Both pane
    /// tabs and the transcript card call the same coordinator method, so a removal on any of them
    /// shows on all three.
    func removeProposedComment(at index: Int, target: PullRequestPaneTarget? = nil) {
        guard let target = target ?? activePaneTarget,
              let proposal = pendingReviewProposal(for: target) else {
            return
        }
        reviewProposalCoordinator?.removeStagedComment(proposalID: proposal.id, at: index)
    }

    /// Brings the anchor's file into the rendered window and expands it, because a comment row is
    /// only ever emitted from a rendered line row — a file beyond `renderedDiffFileCount`, or one
    /// still collapsed, contributes no lines and therefore no comment.
    ///
    /// Does nothing when no file matches. A pull request pushed to since the proposal was made can
    /// strand an anchor, and there is nothing to reveal; the scroll gives up once the diff loads
    /// without the row.
    func revealDiffFile(containing anchor: DiffCommentAnchor, target: PullRequestPaneTarget) {
        guard let session = paneSessions[target],
              let files = session.diffFiles,
              // `DiffFile.path` is `newPath ?? oldPath`, matching how the row builder and the
              // proposal preview both key files.
              let index = files.firstIndex(where: { $0.path == anchor.path }) else {
            return
        }
        let collapseID = FlattenedDiffPreviewRows.fileCollapseID(for: files[index], fileIndex: index)
        mutateSession(target) { session in
            session.renderedDiffFileCount = max(session.renderedDiffFileCount, index + 1)
            session.collapsedDiffFileIDs.remove(collapseID)
        }
    }

    /// Re-runs the reveal for a still-pending scroll once the diff lands. A jump routinely arrives
    /// while the diff is still loading, when there are no files to search yet.
    func revealPendingCommentScrollFileIfNeeded(target: PullRequestPaneTarget) {
        guard let anchor = paneSessions[target]?.pendingCommentScrollTarget?.anchor else {
            return
        }
        revealDiffFile(containing: anchor, target: target)
    }
}
