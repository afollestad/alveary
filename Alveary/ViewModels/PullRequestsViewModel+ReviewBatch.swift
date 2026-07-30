import Foundation

// The pending review batch: inline-comment composing, remote comment edits, and
// one-call submission. Guarded writes go through the main file's `updateSession`.
extension PullRequestsViewModel {
    var activePaneSession: PullRequestPaneSession? {
        activePaneTarget.flatMap { paneSessions[$0] }
    }

    func openCommentComposer(at anchor: DiffCommentAnchor) {
        mutateActiveSession { session in
            session.composerAnchor = anchor
            session.composerText = session.pendingReview.comments.first { $0.anchor == anchor }?.body ?? ""
            session.composerRemoteCommentID = nil
            session.composerReplyToCommentID = nil
            session.composerError = nil
            session.composerFocusToken = UUID()
            composerDraft = PullRequestCommentDraftBox(markdown: session.composerText)
        }
    }

    /// Opens an empty composer that will reply to the thread's root comment on save.
    func openThreadReplyComposer(at anchor: DiffCommentAnchor, thread: DiffLineCommentThread) {
        guard let replyTarget = thread.replyTargetCommentID else {
            return
        }
        mutateActiveSession { session in
            session.composerAnchor = anchor
            session.composerText = ""
            session.composerRemoteCommentID = nil
            session.composerReplyToCommentID = replyTarget
            session.composerError = nil
            session.composerFocusToken = UUID()
            composerDraft = PullRequestCommentDraftBox(markdown: "")
        }
    }

    /// Opens the composer prefilled with a submitted comment the viewer may update.
    func openRemoteCommentEditor(at anchor: DiffCommentAnchor, comment: DiffLineComment) {
        guard let remoteID = comment.remoteID, comment.canEdit else {
            return
        }
        mutateActiveSession { session in
            session.composerAnchor = anchor
            session.composerText = comment.bodyMarkdown
            session.composerRemoteCommentID = remoteID
            session.composerReplyToCommentID = nil
            session.composerError = nil
            session.composerFocusToken = UUID()
            composerDraft = PullRequestCommentDraftBox(markdown: comment.bodyMarkdown)
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
            session.composerReplyToCommentID = nil
            session.composerError = nil
        }
        composerDraft = nil
    }

    /// Saves the composer: a remote edit patches the submitted comment on GitHub,
    /// otherwise the draft joins the pending batch, replacing any existing pending
    /// comment on the same anchor.
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
        mutateActiveSession { session in
            guard let anchor = session.composerAnchor else {
                return
            }
            let body = session.composerText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else {
                return
            }
            if let index = session.pendingReview.comments.firstIndex(where: { $0.anchor == anchor }) {
                session.pendingReview.comments[index].body = body
            } else {
                session.pendingReview.comments.append(PendingReviewComment(id: UUID(), anchor: anchor, body: body))
            }
            session.pendingReview.submissionError = nil
            session.composerAnchor = nil
            session.composerText = ""
            composerDraft = nil
        }
    }

    /// Remote edits and thread replies save straight to GitHub instead of joining
    /// the pending batch (see `PullRequestsViewModel+RemoteComments.swift`).
    /// Returns `true` when the composer state claimed the save.
    private func dispatchImmediateComposerSendIfNeeded() -> Bool {
        guard let target = activePaneTarget, let session = paneSessions[target] else {
            return false
        }
        let body = session.composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let remoteID = session.composerRemoteCommentID {
            if !body.isEmpty {
                dispatchRemoteCommentEdit(target: target, session: session, commentID: remoteID, body: body)
            }
            return true
        }
        if let replyTarget = session.composerReplyToCommentID {
            if !body.isEmpty {
                dispatchThreadReply(target: target, session: session, rootCommentID: replyTarget, body: body)
            }
            return true
        }
        return false
    }

    // MARK: - Thread resolution

    /// Resolves or unresolves a review thread. The flag flips optimistically —
    /// no refetch — and a failed mutation flips it back.
    func setThreadResolved(threadID: String?, resolved: Bool) {
        guard let target = activePaneTarget,
              let session = paneSessions[target],
              let threadID else {
            return
        }
        let generation = session.generation
        guard updateSession(target, generation: generation, { session in
            session.detail?.setThreadResolved(threadID: threadID, resolved: resolved)
            session.composerError = nil
        }) else {
            return
        }
        Task {
            do {
                try await service.setReviewThreadResolved(threadID: threadID, resolved: resolved)
            } catch {
                updateSession(target, generation: generation) { session in
                    session.detail?.setThreadResolved(threadID: threadID, resolved: !resolved)
                    session.composerError = error.localizedDescription
                }
            }
        }
    }

    /// Re-requests a review, then refetches so the reviewer flips back to the
    /// pending question mark (which also hides the button, like GitHub). Failures
    /// surface beside the Reviewers section — the user is on the Overview tab,
    /// not Files, when this action fails.
    func reRequestReview(from login: String) {
        guard let target = activePaneTarget,
              let session = paneSessions[target],
              !session.reRequestsInFlight.contains(login) else {
            return
        }
        let generation = session.generation
        updateSession(target, generation: generation) { session in
            session.reviewersError = nil
            session.reRequestsInFlight.insert(login)
        }
        Task {
            do {
                try await service.requestReview(target.identifier, reviewerLogin: login)
                guard updateSession(target, generation: generation, { session in
                    session.isLoadingDetail = true
                }) else {
                    return
                }
                await loadDetail(target: target, generation: generation) { session in
                    session.reRequestsInFlight.remove(login)
                }
            } catch {
                updateSession(target, generation: generation) { session in
                    session.reviewersError = error.localizedDescription
                    session.reRequestsInFlight.remove(login)
                }
            }
        }
    }

    func clearReviewersError() {
        mutateActiveSession { session in
            session.reviewersError = nil
        }
    }

    // MARK: - Reactions

    /// Toggles the viewer's reaction on any reactable subject (issue comment,
    /// review, or review-thread comment). The change applies optimistically —
    /// no refetch — and a failed mutation applies the inverse toggle to revert.
    func toggleReaction(subjectID: String?, content: String, viewerHasReacted: Bool) {
        guard let target = activePaneTarget,
              let session = paneSessions[target],
              let subjectID,
              let reactionContent = PullRequestReactionContent(rawValue: content) else {
            return
        }
        let generation = session.generation
        guard updateSession(target, generation: generation, { session in
            session.detail?.applyViewerReaction(subjectID: subjectID, content: reactionContent, add: !viewerHasReacted)
            session.composerError = nil
        }) else {
            return
        }
        Task {
            await applyReactionToggle(
                target: target,
                generation: generation,
                nodeID: subjectID,
                content: reactionContent,
                removing: viewerHasReacted
            )
        }
    }

    private func applyReactionToggle(
        target: PullRequestPaneTarget,
        generation: UUID,
        nodeID: String,
        content: PullRequestReactionContent,
        removing: Bool
    ) async {
        do {
            if removing {
                try await service.removeReaction(subjectID: nodeID, content: content)
            } else {
                try await service.addReaction(subjectID: nodeID, content: content)
            }
        } catch {
            // Undo the optimistic toggle and reuse the comment-action error surface
            // (banner atop the Files tab).
            updateSession(target, generation: generation) { session in
                session.detail?.applyViewerReaction(subjectID: nodeID, content: content, add: removing)
                session.composerError = error.localizedDescription
            }
        }
    }

    func removePendingComment(at anchor: DiffCommentAnchor) {
        mutateActiveSession { session in
            session.pendingReview.comments.removeAll { $0.anchor == anchor }
            if session.composerAnchor == anchor {
                session.composerAnchor = nil
                session.composerText = ""
            }
        }
    }

    func updateOverallReviewComment(_ text: String) {
        mutateActiveSession { session in
            session.pendingReview.overallComment = text
        }
    }

    static func canSubmitReview(event: PullRequestReviewEvent, draft: PendingReviewDraft) -> Bool {
        let hasOverallComment = !draft.overallComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch event {
        case .approve:
            return true
        case .requestChanges:
            return hasOverallComment
        case .comment:
            return hasOverallComment || !draft.comments.isEmpty
        }
    }

    /// Submits the pending batch as one review. Success clears the draft and
    /// refetches the detail and list; failure keeps the batch intact.
    @discardableResult
    func submitReview(event: PullRequestReviewEvent) async -> Bool {
        guard let target = activePaneTarget,
              let session = paneSessions[target],
              !session.pendingReview.isSubmitting,
              Self.canSubmitReview(event: event, draft: session.pendingReview) else {
            return false
        }
        let generation = session.generation
        let draft = session.pendingReview
        updateSession(target, generation: generation) { session in
            session.pendingReview.isSubmitting = true
            session.pendingReview.submissionError = nil
        }

        let submission = PendingReviewSubmission(
            event: event,
            body: draft.overallComment.trimmingCharacters(in: .whitespacesAndNewlines),
            comments: draft.comments.map { comment in
                PendingReviewSubmission.InlineComment(
                    path: comment.anchor.path,
                    line: comment.anchor.line,
                    side: comment.anchor.side == .left ? .left : .right,
                    body: comment.body
                )
            }
        )
        do {
            try await service.submitReview(target.identifier, submission: submission)
            // The pending batch stays visible (with `isSubmitting` keeping the
            // footer disabled) until the refetched detail lands; clearing it in the
            // same write as the new detail avoids a frame with no comments at all.
            await loadDetail(target: target, generation: generation) { session in
                session.pendingReview = PendingReviewDraft()
                session.composerAnchor = nil
                session.composerText = ""
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
