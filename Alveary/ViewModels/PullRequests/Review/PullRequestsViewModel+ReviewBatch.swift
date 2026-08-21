import Foundation

// Comment composing and review submission. Opening a composer and routing its
// save live here; the sends themselves live in the `+PendingComments` and
// `+RemoteComments` companions. Guarded writes go through the main file's
// `updateSession`.
extension PullRequestsViewModel {
    var activePaneSession: PullRequestPaneSession? {
        activePaneTarget.flatMap { paneSessions[$0] }
    }

    func openCommentComposer(at anchor: DiffCommentAnchor) {
        mutateActiveSession { session in
            session.composerAnchor = anchor
            session.composerText = ""
            session.composerRemoteCommentID = nil
            session.composerPendingCommentNodeID = nil
            session.composerIssueCommentID = nil
            session.composerReviewID = nil
            session.composerReplyToCommentID = nil
            session.composerError = nil
            session.composerFocusToken = UUID()
            composerDraft = PullRequestCommentDraftBox(markdown: "")
        }
    }

    /// Opens the inline editor for one of the viewer's own unsubmitted comments.
    /// `anchor` is nil when opened from the Overview timeline, which has no diff row.
    func openPendingCommentEditor(nodeID: String, body: String, anchor: DiffCommentAnchor?) {
        mutateActiveSession { session in
            session.composerAnchor = anchor
            session.composerText = body
            session.composerRemoteCommentID = nil
            session.composerPendingCommentNodeID = nodeID
            session.composerIssueCommentID = nil
            session.composerReviewID = nil
            session.composerReplyToCommentID = nil
            session.composerError = nil
            session.composerFocusToken = UUID()
            composerDraft = PullRequestCommentDraftBox(markdown: body)
        }
    }

    /// Opens an empty composer that will reply to the thread's root comment on save.
    func openThreadReplyComposer(at anchor: DiffCommentAnchor, thread: DiffLineCommentThread) {
        guard let replyTarget = thread.replyTargetCommentID else {
            return
        }
        openReplyComposer(replyTarget: replyTarget, anchor: anchor)
    }

    /// Overview entry point for the same reply flow; the timeline has no diff
    /// anchor, so the editor renders inline in the thread instead of a diff row.
    func openThreadReplyComposer(_ thread: PullRequestReviewThread) {
        guard let replyTarget = thread.replyTargetCommentID else {
            return
        }
        openReplyComposer(replyTarget: replyTarget, anchor: nil)
    }

    private func openReplyComposer(replyTarget: Int, anchor: DiffCommentAnchor?) {
        mutateActiveSession { session in
            session.composerAnchor = anchor
            session.composerText = ""
            session.composerRemoteCommentID = nil
            session.composerPendingCommentNodeID = nil
            session.composerIssueCommentID = nil
            session.composerReviewID = nil
            session.composerReplyToCommentID = replyTarget
            session.composerError = nil
            session.composerFocusToken = UUID()
            composerDraft = PullRequestCommentDraftBox(markdown: "")
        }
    }

    /// Opens the composer prefilled with a review-thread comment the viewer may
    /// update. A pending comment takes the GraphQL path; a submitted one PATCHes
    /// `pulls/comments/{id}`.
    func openRemoteCommentEditor(at anchor: DiffCommentAnchor, comment: DiffLineComment) {
        guard comment.canEdit else {
            return
        }
        if comment.isPending {
            guard let nodeID = comment.nodeID else {
                return
            }
            openPendingCommentEditor(nodeID: nodeID, body: comment.bodyMarkdown, anchor: anchor)
            return
        }
        guard let remoteID = comment.remoteID else {
            return
        }
        openThreadCommentEditor(remoteID: remoteID, body: comment.bodyMarkdown, anchor: anchor)
    }

    /// Overview entry point for the same review-thread comment edit the Changes
    /// tab offers; the timeline has no diff anchor, so none is recorded. The
    /// pending/submitted split is the same one the Changes tab makes.
    func openThreadCommentEditor(_ comment: PullRequestComment) {
        guard comment.viewerCanUpdate else {
            return
        }
        if comment.isPending {
            guard let nodeID = comment.nodeID else {
                return
            }
            openPendingCommentEditor(nodeID: nodeID, body: comment.bodyMarkdown, anchor: nil)
            return
        }
        guard let remoteID = comment.databaseId else {
            return
        }
        openThreadCommentEditor(remoteID: remoteID, body: comment.bodyMarkdown, anchor: nil)
    }

    /// Opens the inline editor for a top-level conversation comment the viewer
    /// may update; saves patch `issues/comments/{id}` instead of the review batch.
    func openIssueCommentEditor(_ comment: PullRequestComment) {
        guard let remoteID = comment.databaseId, comment.viewerCanUpdate else {
            return
        }
        mutateActiveSession { session in
            session.composerAnchor = nil
            session.composerText = comment.bodyMarkdown
            session.composerRemoteCommentID = nil
            session.composerPendingCommentNodeID = nil
            session.composerIssueCommentID = remoteID
            session.composerReviewID = nil
            session.composerReplyToCommentID = nil
            session.composerError = nil
            session.composerFocusToken = UUID()
            composerDraft = PullRequestCommentDraftBox(markdown: comment.bodyMarkdown)
        }
    }

    /// Opens the inline editor for a review's summary body the viewer may update;
    /// saves PUT `pulls/{number}/reviews/{id}`. Submitted reviews cannot be
    /// deleted, so this is the review card's only remote action.
    func openReviewBodyEditor(_ review: PullRequestReview) {
        guard let remoteID = review.databaseId, review.viewerCanUpdate else {
            return
        }
        mutateActiveSession { session in
            session.composerAnchor = nil
            session.composerText = review.bodyMarkdown
            session.composerRemoteCommentID = nil
            session.composerPendingCommentNodeID = nil
            session.composerIssueCommentID = nil
            session.composerReviewID = remoteID
            session.composerReplyToCommentID = nil
            session.composerError = nil
            session.composerFocusToken = UUID()
            composerDraft = PullRequestCommentDraftBox(markdown: review.bodyMarkdown)
        }
    }

    private func openThreadCommentEditor(remoteID: Int, body: String, anchor: DiffCommentAnchor?) {
        mutateActiveSession { session in
            session.composerAnchor = anchor
            session.composerText = body
            session.composerRemoteCommentID = remoteID
            session.composerPendingCommentNodeID = nil
            session.composerIssueCommentID = nil
            session.composerReviewID = nil
            session.composerReplyToCommentID = nil
            session.composerError = nil
            session.composerFocusToken = UUID()
            composerDraft = PullRequestCommentDraftBox(markdown: body)
        }
    }

    /// Opens the Overview description in the shared inline editor. GitHub gates
    /// body edits on `viewerCanUpdate`, not authorship, like comment menus.
    func openDescriptionEditor() {
        guard let detail = activePaneSession?.detail, detail.viewerCanUpdate else {
            return
        }
        mutateActiveSession { session in
            session.composerAnchor = nil
            session.composerText = detail.bodyMarkdown
            session.composerRemoteCommentID = nil
            session.composerPendingCommentNodeID = nil
            session.composerIssueCommentID = nil
            session.composerReviewID = nil
            session.composerReplyToCommentID = nil
            session.isEditingDescription = true
            session.composerError = nil
            session.composerFocusToken = UUID()
            composerDraft = PullRequestCommentDraftBox(markdown: detail.bodyMarkdown)
        }
    }

    func updateComposerText(_ text: String) {
        mutateActiveSession { session in
            session.composerText = text
        }
        composerDraft?.replaceText(text)
    }

    /// The mounted composer consumed the focus request; stop re-requesting.
    func consumeComposerFocusToken() {
        mutateActiveSession { session in
            session.composerFocusToken = nil
        }
    }

    func cancelCommentComposer() {
        mutateActiveSession { session in
            session.composerAnchor = nil
            session.composerText = ""
            session.composerRemoteCommentID = nil
            session.composerPendingCommentNodeID = nil
            session.composerIssueCommentID = nil
            session.composerReviewID = nil
            session.composerReplyToCommentID = nil
            session.isEditingDescription = false
            session.composerError = nil
        }
        composerDraft = nil
    }

    /// Saves the composer. Every path posts to GitHub immediately: a remote edit
    /// patches the submitted comment, and a new inline comment becomes a pending
    /// review comment on the viewer's draft review, creating that review first if
    /// it does not exist yet. The one exception is a new inline comment written
    /// while a review proposal is pending for this pull request — that joins the
    /// proposal's staged comments instead, reaching nothing until it is submitted.
    func saveComposerComment() {
        // The BlockInputKit store owns the live text; serialize it once at save.
        if let composerDraft {
            mutateActiveSession { session in
                session.composerText = composerDraft.markdown
            }
        }
        if dispatchImmediateComposerSendIfNeeded() {
            return
        }
        guard let target = activePaneTarget, let session = paneSessions[target] else {
            return
        }
        guard let anchor = session.composerAnchor else {
            return
        }
        let body = session.composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            return
        }
        if let proposal = pendingReviewProposal(for: target) {
            stageProposedComment(
                proposalID: proposal.id,
                target: target,
                generation: session.generation,
                anchor: anchor,
                body: body
            )
            return
        }
        dispatchPendingCommentCreation(target: target, session: session, anchor: anchor, body: body)
    }

    /// Remote edits, pending-comment edits, and thread replies all save straight
    /// to GitHub (see `PullRequestsViewModel+RemoteComments.swift`). Returns
    /// `true` when the composer state claimed the save.
    private func dispatchImmediateComposerSendIfNeeded() -> Bool {
        guard let target = activePaneTarget, let session = paneSessions[target] else {
            return false
        }
        let body = session.composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let send = immediateComposerSend(for: session, target: target, body: body) else {
            return false
        }
        // An empty body cancels every edit but a description, which may legitimately
        // be cleared — that case is decided in `immediateComposerSend`.
        if !body.isEmpty || session.isEditingDescription {
            send()
        }
        return true
    }

    /// Picks the one save the composer state means, or nil when the composer is
    /// writing a brand-new inline comment (which is not an immediate send).
    private func immediateComposerSend(
        for session: PullRequestPaneSession,
        target: PullRequestPaneTarget,
        body: String
    ) -> (() -> Void)? {
        if let remoteID = session.composerRemoteCommentID {
            return { self.dispatchRemoteCommentEdit(target: target, session: session, commentID: remoteID, body: body) }
        }
        if let nodeID = session.composerPendingCommentNodeID {
            return { self.dispatchPendingCommentEdit(target: target, session: session, nodeID: nodeID, body: body) }
        }
        if let issueCommentID = session.composerIssueCommentID {
            return {
                self.dispatchIssueCommentEdit(target: target, session: session, commentID: issueCommentID, body: body)
            }
        }
        if let reviewID = session.composerReviewID {
            return { self.dispatchReviewBodyEdit(target: target, session: session, reviewID: reviewID, body: body) }
        }
        if let replyTarget = session.composerReplyToCommentID {
            return {
                self.dispatchThreadReply(target: target, session: session, rootCommentID: replyTarget, body: body)
            }
        }
        if session.isEditingDescription {
            return { self.dispatchDescriptionEdit(target: target, session: session, body: body) }
        }
        return nil
    }

    func updateOverallReviewComment(_ text: String) {
        mutateActiveSession { session in
            session.pendingReview.overallComment = text
        }
    }

    /// `pendingCommentCount` is whatever the caller's submit would actually
    /// publish: the comments already on GitHub, plus any a review proposal has
    /// staged when the submit routes through the coordinator. The pane sums both
    /// in `submittableCommentCount(for:)`; the card counts its own snapshot.
    static func canSubmitReview(
        event: PullRequestReviewEvent,
        draft: PendingReviewDraft,
        pendingCommentCount: Int
    ) -> Bool {
        let hasOverallComment = !draft.overallComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch event {
        case .approve:
            return true
        case .requestChanges:
            return hasOverallComment
        case .comment:
            return hasOverallComment || pendingCommentCount > 0
        }
    }

    /// Submits the review. With a pending review on GitHub this publishes *that*
    /// review — every comment already attached to it — rather than opening a
    /// second one beside it; with none, it posts a summary-only review.
    /// Success refetches the detail and list; failure leaves the pending comments
    /// untouched on GitHub and surfaces the error.
    ///
    /// A pending review proposal for this pull request routes the whole submission
    /// through the coordinator instead, so the staged comments are published with
    /// the draft's rather than left behind by it.
    @discardableResult
    func submitReview(event: PullRequestReviewEvent) async -> Bool {
        guard let target = activePaneTarget,
              let session = paneSessions[target],
              !session.pendingReview.isSubmitting else {
            return false
        }
        // The proposal's own body counts as the summary when the composer is empty, because that is
        // what `confirm` would publish; `resolvedReviewSummary` owns the precedence both gates read.
        var validated = session.pendingReview
        validated.overallComment = resolvedReviewSummary(for: target, session: session)
        guard Self.canSubmitReview(
            event: event,
            draft: validated,
            pendingCommentCount: submittableCommentCount(for: target, session: session)
        ) else {
            return false
        }
        if let proposal = pendingReviewProposal(for: target) {
            return await submitProposedReview(proposal, event: event, target: target, session: session)
        }
        let generation = session.generation
        let body = session.pendingReview.overallComment.trimmingCharacters(in: .whitespacesAndNewlines)
        let pendingReviewNodeID = session.detail?.pendingReviewNodeID
        updateSession(target, generation: generation) { session in
            session.pendingReview.isSubmitting = true
            session.pendingReview.submissionError = nil
        }

        do {
            if let pendingReviewNodeID {
                try await service.submitPendingReview(
                    reviewNodeID: pendingReviewNodeID,
                    event: event,
                    body: body
                )
            } else {
                // No draft review exists, so there is nothing to finish: post the
                // verdict and summary as a review of its own.
                try await service.submitReview(target.identifier, event: event, body: body)
            }
            // The pending comments are already rendered from `session.detail`, so
            // they stay on screen through the refetch that reclassifies them as
            // submitted; only the local summary needs clearing.
            await loadDetail(target: target, generation: generation) { session in
                session.pendingReview = PendingReviewDraft()
                session.composerAnchor = nil
                session.composerText = ""
                session.composerPendingCommentNodeID = nil
            }
            requestRefresh()
            return true
        } catch {
            updateSession(target, generation: generation) { session in
                session.pendingReview.isSubmitting = false
                session.pendingReview.submissionError = error.localizedDescription
            }
            return false
        }
    }
}
