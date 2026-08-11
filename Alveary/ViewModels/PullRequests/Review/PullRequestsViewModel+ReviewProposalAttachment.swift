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

    /// Comments a submit from this pane would publish: the viewer's own GitHub draft plus the
    /// pending proposal's staged ones, because a submit with a proposal pending routes through the
    /// coordinator, which writes the staged comments into that same draft before publishing it.
    ///
    /// The footer's count note, the footer's Submit enablement, and `submitReview`'s own guard all
    /// read this one sum, so the button can never offer a submit the guard then silently refuses.
    ///
    /// Takes the session rather than looking it up, for the reason `PullRequestPaneFiles` takes its
    /// target explicitly: the footer resolves for the session it was handed, which is also what
    /// lets a snapshot host render it without opening a pane.
    func submittableCommentCount(
        for target: PullRequestPaneTarget,
        session: PullRequestPaneSession
    ) -> Int {
        (session.detail?.pendingCommentCount ?? 0)
            + (pendingReviewProposal(for: target)?.comments.count ?? 0)
    }

    /// Writes a composed comment into the pending proposal's envelope instead of GitHub's draft.
    ///
    /// Composing in a pane with a review waiting adds to *that* review: a comment written to the
    /// viewer's draft would be published by the same Submit, but would never appear on the
    /// transcript card, so the two surfaces would disagree about what the review says. Nothing
    /// reaches GitHub, so there is no optimistic placeholder to withdraw — the merged annotations
    /// re-derive from the envelope on the next render.
    func stageProposedComment(
        proposalID: String,
        target: PullRequestPaneTarget,
        generation: UUID,
        anchor: DiffCommentAnchor,
        body: String
    ) {
        guard reviewProposalCoordinator?.addStagedComment(
            proposalID: proposalID,
            path: anchor.path,
            line: anchor.line,
            side: anchor.side == .left ? .left : .right,
            body: body
        ) == true else {
            // Leave the composer open with its text intact, like every other composer failure here.
            updateSession(target, generation: generation) { session in
                session.composerError = reviewProposalCoordinator?.errorMessage(forProposalID: proposalID)
                    ?? "Alveary could not add this comment to the review."
            }
            return
        }
        updateSession(target, generation: generation) { session in
            session.composerAnchor = nil
            session.composerText = ""
            session.composerError = nil
            session.pendingReview.submissionError = nil
            composerDraft = nil
        }
    }

    /// Submits through the proposal coordinator so one GitHub review carries both sets: the
    /// coordinator writes the staged comments into the viewer's draft — the same draft the pane's
    /// own pending comments already live in — and publishes it once.
    ///
    /// The summary has two sources. The footer's text wins when it has one, falling back to what
    /// the model proposed, so an untouched footer publishes the proposal's body rather than
    /// blanking it. A successful confirm clears the envelope, so the staged comments drop out of
    /// the pane on the next read and the transcript card resolves as confirmed — no detaching to do.
    func submitProposedReview(
        _ proposal: PullRequestReviewProposalPresentation,
        event: PullRequestReviewEvent,
        target: PullRequestPaneTarget,
        session: PullRequestPaneSession
    ) async -> Bool {
        guard let coordinator = reviewProposalCoordinator else {
            return false
        }
        let generation = session.generation
        let summary = session.pendingReview.overallComment.trimmingCharacters(in: .whitespacesAndNewlines)
        updateSession(target, generation: generation) { session in
            session.pendingReview.isSubmitting = true
            session.pendingReview.submissionError = nil
        }
        guard await coordinator.confirm(
            proposalID: proposal.id,
            event: event,
            bodyOverride: summary.isEmpty ? nil : summary
        ) else {
            updateSession(target, generation: generation) { session in
                session.pendingReview.isSubmitting = false
                session.pendingReview.submissionError = coordinator.errorMessage(forProposalID: proposal.id)
                    ?? "Alveary could not submit this review."
            }
            return false
        }
        // `confirm` refetches only its own copy of the detail, so the pane still holds the
        // pre-submission threads; this is the epilogue the GitHub-draft path runs for that reason.
        await loadDetail(target: target, generation: generation) { session in
            session.pendingReview = PendingReviewDraft()
            session.composerAnchor = nil
            session.composerText = ""
            session.composerPendingCommentNodeID = nil
        }
        requestRefresh()
        return true
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
