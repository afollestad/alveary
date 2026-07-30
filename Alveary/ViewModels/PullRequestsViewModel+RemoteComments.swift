import Foundation

// Immediate remote comment actions — edits, thread replies, and deletion — that
// save straight to GitHub instead of joining the pending batch. All of them apply
// optimistically and revert on failure; only a successful reply refetches, to
// replace its placeholder with the server copy. Guarded writes go through the
// main file's `updateSession`.
extension PullRequestsViewModel {
    // MARK: - Remote edit

    /// Optimistic: the new body renders and the composer closes immediately; a
    /// failed patch restores the old body and reopens the composer.
    func dispatchRemoteCommentEdit(
        target: PullRequestPaneTarget,
        session: PullRequestPaneSession,
        commentID: Int,
        body: String
    ) {
        let anchor = session.composerAnchor
        var previousBody: String?
        guard updateSession(target, generation: session.generation, { session in
            previousBody = session.detail?.updateThreadCommentBody(commentID: commentID, body: body)
            session.composerAnchor = nil
            session.composerText = ""
            session.composerRemoteCommentID = nil
            session.composerError = nil
            composerDraft = nil
        }) else {
            return
        }
        let attempt = RemoteCommentEditAttempt(
            commentID: commentID,
            body: body,
            previousBody: previousBody,
            anchor: anchor
        )
        Task {
            await updateRemoteComment(target: target, generation: session.generation, attempt: attempt)
        }
    }

    /// Failure restores the previous body and reopens the composer with the
    /// attempted text intact. Success never refetches — the local body is exact.
    private func updateRemoteComment(
        target: PullRequestPaneTarget,
        generation: UUID,
        attempt: RemoteCommentEditAttempt
    ) async {
        do {
            try await service.updateReviewComment(
                target.identifier,
                commentID: attempt.commentID,
                body: attempt.body
            )
        } catch {
            updateSession(target, generation: generation) { session in
                if let previousBody = attempt.previousBody {
                    session.detail?.updateThreadCommentBody(commentID: attempt.commentID, body: previousBody)
                }
                session.composerAnchor = attempt.anchor
                session.composerText = attempt.body
                session.composerRemoteCommentID = attempt.commentID
                session.composerError = error.localizedDescription
                session.composerFocusToken = UUID()
                composerDraft = PullRequestCommentDraftBox(markdown: attempt.body)
            }
        }
    }

    // MARK: - Thread replies

    /// Optimistic: the placeholder (attributed to the viewer) joins the thread and
    /// the composer closes immediately; a failed post removes it and reopens the
    /// composer.
    func dispatchThreadReply(
        target: PullRequestPaneTarget,
        session: PullRequestPaneSession,
        rootCommentID: Int,
        body: String
    ) {
        let anchor = session.composerAnchor
        let viewerLogin = session.detail?.viewerLogin
        let viewerAvatarURL = session.detail?.viewerAvatarURL
        guard updateSession(target, generation: session.generation, { session in
            session.detail?.appendThreadReply(
                rootCommentID: rootCommentID,
                comment: PullRequestComment(
                    authorLogin: viewerLogin ?? "You",
                    authorAvatarURL: viewerAvatarURL,
                    bodyMarkdown: body,
                    createdAt: Date()
                )
            )
            session.composerAnchor = nil
            session.composerText = ""
            session.composerReplyToCommentID = nil
            session.composerError = nil
            composerDraft = nil
        }) else {
            return
        }
        Task {
            await submitThreadReply(
                target: target,
                generation: session.generation,
                commentID: rootCommentID,
                body: body,
                anchor: anchor
            )
        }
    }

    /// The optimistic placeholder is already in the thread; success refetches
    /// silently so the server copy (with real ids and author) replaces it, and
    /// failure removes it and reopens the composer with the text intact.
    private func submitThreadReply(
        target: PullRequestPaneTarget,
        generation: UUID,
        commentID: Int,
        body: String,
        anchor: DiffCommentAnchor?
    ) async {
        do {
            try await service.replyToReviewComment(target.identifier, commentID: commentID, body: body)
            guard updateSession(target, generation: generation, { session in
                session.isLoadingDetail = true
            }) else {
                return
            }
            await loadDetail(target: target, generation: generation)
        } catch {
            updateSession(target, generation: generation) { session in
                session.detail?.removeOptimisticReply(rootCommentID: commentID, body: body)
                session.composerAnchor = anchor
                session.composerText = body
                session.composerReplyToCommentID = commentID
                session.composerError = error.localizedDescription
                session.composerFocusToken = UUID()
                composerDraft = PullRequestCommentDraftBox(markdown: body)
            }
        }
    }

    // MARK: - Remote comment deletion

    /// Arms the destructive confirmation; the dialog's Delete calls the confirm method.
    func requestDeleteRemoteComment(at anchor: DiffCommentAnchor, comment: DiffLineComment) {
        guard let remoteID = comment.remoteID, comment.canDelete else {
            return
        }
        mutateActiveSession { session in
            session.pendingRemoteCommentDeletion = PendingRemoteCommentDeletion(
                anchor: anchor,
                remoteID: remoteID,
                bodyPreview: comment.bodyMarkdown
            )
        }
    }

    func cancelRemoteCommentDeletion() {
        mutateActiveSession { session in
            session.pendingRemoteCommentDeletion = nil
        }
    }

    /// Clear pending state before awaiting, per the destructive-confirmation convention.
    func confirmRemoteCommentDeletion() {
        guard let target = activePaneTarget,
              let session = paneSessions[target],
              let pending = session.pendingRemoteCommentDeletion else {
            return
        }
        mutateActiveSession { session in
            session.pendingRemoteCommentDeletion = nil
        }
        Task {
            await deleteRemoteComment(
                target: target,
                generation: session.generation,
                commentID: pending.remoteID
            )
        }
    }

    func clearCommentActionError() {
        mutateActiveSession { session in
            session.composerError = nil
        }
    }

    /// The comment (and an emptied thread) is removed optimistically before the
    /// DELETE; failure reinserts it. Success never refetches.
    private func deleteRemoteComment(
        target: PullRequestPaneTarget,
        generation: UUID,
        commentID: Int
    ) async {
        var removed: PullRequestDetail.RemovedThreadComment?
        guard updateSession(target, generation: generation, { session in
            removed = session.detail?.removeThreadComment(commentID: commentID)
            // Close the composer if it was editing the comment that just vanished.
            if session.composerRemoteCommentID == commentID {
                session.composerAnchor = nil
                session.composerText = ""
                session.composerRemoteCommentID = nil
                composerDraft = nil
            }
            session.composerError = nil
        }) else {
            return
        }
        do {
            try await service.deleteReviewComment(target.identifier, commentID: commentID)
        } catch {
            updateSession(target, generation: generation) { session in
                if let removed {
                    session.detail?.restoreThreadComment(removed)
                }
                session.composerError = error.localizedDescription
            }
        }
    }
}

/// One optimistic remote-edit attempt, bundled so the failure path can revert
/// the body and reopen the composer where the user left it.
struct RemoteCommentEditAttempt: Sendable {
    let commentID: Int
    let body: String
    let previousBody: String?
    let anchor: DiffCommentAnchor?
}
