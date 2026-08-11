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

    /// Optimistic edit of a top-level conversation comment, mirroring
    /// `dispatchRemoteCommentEdit` against the `issues/comments/{id}` endpoint.
    func dispatchIssueCommentEdit(
        target: PullRequestPaneTarget,
        session: PullRequestPaneSession,
        commentID: Int,
        body: String
    ) {
        var previousBody: String?
        guard updateSession(target, generation: session.generation, { session in
            previousBody = session.detail?.updateIssueCommentBody(commentID: commentID, body: body)
            session.composerText = ""
            session.composerIssueCommentID = nil
            session.composerError = nil
            composerDraft = nil
        }) else {
            return
        }
        let generation = session.generation
        Task {
            await updateIssueComment(
                target: target,
                generation: generation,
                commentID: commentID,
                body: body,
                previousBody: previousBody
            )
        }
    }

    /// Failure restores the previous body and reopens the inline editor with the
    /// attempted text intact. Success never refetches — the local body is exact.
    private func updateIssueComment(
        target: PullRequestPaneTarget,
        generation: UUID,
        commentID: Int,
        body: String,
        previousBody: String?
    ) async {
        do {
            try await service.updateIssueComment(target.identifier, commentID: commentID, body: body)
        } catch {
            updateSession(target, generation: generation) { session in
                if let previousBody {
                    session.detail?.updateIssueCommentBody(commentID: commentID, body: previousBody)
                }
                session.composerText = body
                session.composerIssueCommentID = commentID
                session.composerError = error.localizedDescription
                session.composerFocusToken = UUID()
                composerDraft = PullRequestCommentDraftBox(markdown: body)
            }
        }
    }

    /// Optimistic edit of a review's summary body, mirroring
    /// `dispatchIssueCommentEdit` against the `pulls/{number}/reviews/{id}` endpoint.
    func dispatchReviewBodyEdit(
        target: PullRequestPaneTarget,
        session: PullRequestPaneSession,
        reviewID: Int,
        body: String
    ) {
        var previousBody: String?
        guard updateSession(target, generation: session.generation, { session in
            previousBody = session.detail?.updateReviewBody(reviewID: reviewID, body: body)
            session.composerText = ""
            session.composerReviewID = nil
            session.composerError = nil
            composerDraft = nil
        }) else {
            return
        }
        let generation = session.generation
        Task {
            await updateReviewBody(
                target: target,
                generation: generation,
                reviewID: reviewID,
                body: body,
                previousBody: previousBody
            )
        }
    }

    /// Failure restores the previous body and reopens the inline editor with the
    /// attempted text intact. Success never refetches — the local body is exact.
    private func updateReviewBody(
        target: PullRequestPaneTarget,
        generation: UUID,
        reviewID: Int,
        body: String,
        previousBody: String?
    ) async {
        do {
            try await service.updateReview(target.identifier, reviewID: reviewID, body: body)
        } catch {
            updateSession(target, generation: generation) { session in
                if let previousBody {
                    session.detail?.updateReviewBody(reviewID: reviewID, body: previousBody)
                }
                session.composerText = body
                session.composerReviewID = reviewID
                session.composerError = error.localizedDescription
                session.composerFocusToken = UUID()
                composerDraft = PullRequestCommentDraftBox(markdown: body)
            }
        }
    }

    // MARK: - Description

    /// Optimistic like every other remote edit: the body swaps locally and the
    /// editor closes before the PATCH.
    func dispatchDescriptionEdit(
        target: PullRequestPaneTarget,
        session: PullRequestPaneSession,
        body: String
    ) {
        var previousBody: String?
        guard updateSession(target, generation: session.generation, { session in
            previousBody = session.detail?.bodyMarkdown
            session.detail?.bodyMarkdown = body
            session.composerText = ""
            session.isEditingDescription = false
            session.composerError = nil
            composerDraft = nil
        }) else {
            return
        }
        let generation = session.generation
        Task {
            await updateDescription(
                target: target,
                generation: generation,
                body: body,
                previousBody: previousBody
            )
        }
    }

    /// Failure restores the previous description and reopens the editor with the
    /// attempted text intact. Success never refetches — the local body is exact.
    private func updateDescription(
        target: PullRequestPaneTarget,
        generation: UUID,
        body: String,
        previousBody: String?
    ) async {
        do {
            try await service.updatePullRequestBody(target.identifier, body: body)
        } catch {
            updateSession(target, generation: generation) { session in
                if let previousBody {
                    session.detail?.bodyMarkdown = previousBody
                }
                session.composerText = body
                session.isEditingDescription = true
                session.composerError = error.localizedDescription
                session.composerFocusToken = UUID()
                composerDraft = PullRequestCommentDraftBox(markdown: body)
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
    func requestDeleteRemoteComment(comment: DiffLineComment) {
        guard comment.canDelete, !comment.isPending, let remoteID = comment.remoteID else {
            return
        }
        armRemoteCommentDeletion(kind: .reviewComment, remoteID: remoteID)
    }

    /// Overview entry point for deleting a review-thread comment; same
    /// confirmation and DELETE as the Changes tab. A pending comment skips the
    /// confirmation — nothing is published yet — and deletes over GraphQL.
    func requestDeleteThreadComment(_ comment: PullRequestComment) {
        guard comment.viewerCanDelete else {
            return
        }
        if comment.isPending {
            if let nodeID = comment.nodeID {
                deletePendingComment(nodeID: nodeID)
            }
            return
        }
        guard let remoteID = comment.databaseId else {
            return
        }
        armRemoteCommentDeletion(kind: .reviewComment, remoteID: remoteID)
    }

    /// Arms deletion of a top-level conversation comment (`issues/comments/{id}`).
    func requestDeleteIssueComment(_ comment: PullRequestComment) {
        guard let remoteID = comment.databaseId, comment.viewerCanDelete else {
            return
        }
        armRemoteCommentDeletion(kind: .issueComment, remoteID: remoteID)
    }

    private func armRemoteCommentDeletion(kind: PendingRemoteCommentDeletion.Kind, remoteID: Int) {
        mutateActiveSession { session in
            session.pendingRemoteCommentDeletion = PendingRemoteCommentDeletion(kind: kind, remoteID: remoteID)
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
            switch pending.kind {
            case .reviewComment:
                await deleteRemoteComment(
                    target: target,
                    generation: session.generation,
                    commentID: pending.remoteID
                )
            case .issueComment:
                await deleteIssueComment(
                    target: target,
                    generation: session.generation,
                    commentID: pending.remoteID
                )
            }
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

    /// Optimistic deletion of a top-level conversation comment; failure reinserts
    /// it where it was. Success never refetches.
    private func deleteIssueComment(
        target: PullRequestPaneTarget,
        generation: UUID,
        commentID: Int
    ) async {
        var removed: PullRequestDetail.RemovedIssueComment?
        guard updateSession(target, generation: generation, { session in
            removed = session.detail?.removeIssueComment(commentID: commentID)
            // Close the inline editor if it was editing the comment that just vanished.
            if session.composerIssueCommentID == commentID {
                session.composerText = ""
                session.composerIssueCommentID = nil
                composerDraft = nil
            }
            session.composerError = nil
        }) else {
            return
        }
        do {
            try await service.deleteIssueComment(target.identifier, commentID: commentID)
        } catch {
            updateSession(target, generation: generation) { session in
                if let removed {
                    session.detail?.restoreIssueComment(removed)
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
