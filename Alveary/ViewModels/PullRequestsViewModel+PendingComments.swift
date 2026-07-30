import Foundation

// Inline review comments. They post to GitHub the moment they are saved, as
// comments on the viewer's pending review, so they show up on github.com and
// survive quitting the app. Like every other comment action here they apply
// optimistically and revert on failure; guarded writes go through the main
// file's `updateSession`.
extension PullRequestsViewModel {
    // MARK: - Create

    /// Renders the comment immediately, then posts it. The pending review is
    /// created first when this is the review's first comment.
    func dispatchPendingCommentCreation(
        target: PullRequestPaneTarget,
        session: PullRequestPaneSession,
        anchor: DiffCommentAnchor,
        body: String
    ) {
        guard let pullRequestNodeID = session.detail?.nodeID else {
            mutateActiveSession { session in
                session.composerError = "This pull request is still loading."
            }
            return
        }
        let generation = session.generation
        let placeholderID = PullRequestDetail.placeholderThreadNodeID()
        let placeholder = Self.makePlaceholderPendingThread(
            id: placeholderID,
            anchor: anchor,
            body: body,
            detail: session.detail
        )
        guard updateSession(target, generation: generation, { session in
            session.detail?.upsertReviewThread(placeholder)
            session.composerAnchor = nil
            session.composerText = ""
            session.composerError = nil
            session.pendingReview.submissionError = nil
            composerDraft = nil
        }) else {
            return
        }
        let attempt = PendingCommentCreation(
            pullRequestNodeID: pullRequestNodeID,
            placeholderID: placeholderID,
            anchor: anchor,
            body: body
        )
        Task {
            await createPendingComment(target: target, generation: generation, attempt: attempt)
        }
    }

    private func createPendingComment(
        target: PullRequestPaneTarget,
        generation: UUID,
        attempt: PendingCommentCreation
    ) async {
        do {
            let reviewNodeID = try await resolvePendingReviewNodeID(
                target: target,
                generation: generation,
                pullRequestNodeID: attempt.pullRequestNodeID
            )
            let thread = try await service.addPendingReviewComment(
                reviewNodeID: reviewNodeID,
                path: attempt.anchor.path,
                line: attempt.anchor.line,
                side: attempt.anchor.side == .left ? .left : .right,
                body: attempt.body
            )
            updateSession(target, generation: generation) { session in
                // Swapping in the server copy is what unlocks edit and delete:
                // the placeholder carries no comment node id.
                session.detail?.replaceReviewThread(nodeID: attempt.placeholderID, with: thread)
            }
        } catch {
            updateSession(target, generation: generation) { session in
                session.detail?.removeReviewThread(nodeID: attempt.placeholderID)
                // Reopen the composer with the text intact so nothing typed is lost.
                session.composerAnchor = attempt.anchor
                session.composerText = attempt.body
                session.composerError = error.localizedDescription
                session.composerFocusToken = UUID()
                composerDraft = PullRequestCommentDraftBox(markdown: attempt.body)
            }
        }
    }

    /// GitHub allows one pending review per viewer per pull request, so two
    /// comments saved in quick succession must not each create one — the second
    /// `addPullRequestReview` is rejected and its comment would be lost. The first
    /// caller stores its create task; the rest await that same task. A failed
    /// create clears the slot so the next attempt may retry.
    private func resolvePendingReviewNodeID(
        target: PullRequestPaneTarget,
        generation: UUID,
        pullRequestNodeID: String
    ) async throws -> String {
        if let existing = paneSessions[target]?.detail?.pendingReviewNodeID {
            return existing
        }
        if let inFlight = pendingReviewCreationTasks[target] {
            return try await inFlight.value
        }
        let creation = Task { [service] in
            try await service.createPendingReview(pullRequestNodeID: pullRequestNodeID)
        }
        pendingReviewCreationTasks[target] = creation
        defer {
            pendingReviewCreationTasks[target] = nil
        }
        let reviewNodeID = try await creation.value
        updateSession(target, generation: generation) { session in
            session.detail?.pendingReviewNodeID = reviewNodeID
        }
        return reviewNodeID
    }

    /// The comment as it renders before GitHub answers: the viewer's identity from
    /// the detail query, no ids, so no edit/delete menu and no reactions until the
    /// real thread replaces it.
    private static func makePlaceholderPendingThread(
        id: String,
        anchor: DiffCommentAnchor,
        body: String,
        detail: PullRequestDetail?
    ) -> PullRequestReviewThread {
        PullRequestReviewThread(
            path: anchor.path,
            line: anchor.line,
            side: anchor.side == .left ? .left : .right,
            isResolved: false,
            isOutdated: false,
            comments: [
                PullRequestComment(
                    authorLogin: detail?.viewerLogin ?? "You",
                    authorAvatarURL: detail?.viewerAvatarURL,
                    bodyMarkdown: body,
                    createdAt: Date(),
                    isPending: true
                )
            ],
            nodeID: id
        )
    }

    // MARK: - Edit

    /// Optimistic: the new body renders and the editor closes immediately; a
    /// failed mutation restores the old body and reopens the editor.
    func dispatchPendingCommentEdit(
        target: PullRequestPaneTarget,
        session: PullRequestPaneSession,
        nodeID: String,
        body: String
    ) {
        let anchor = session.composerAnchor
        let generation = session.generation
        var previousBody: String?
        guard updateSession(target, generation: generation, { session in
            previousBody = session.detail?.updateThreadCommentBody(nodeID: nodeID, body: body)
            session.composerAnchor = nil
            session.composerText = ""
            session.composerPendingCommentNodeID = nil
            session.composerError = nil
            composerDraft = nil
        }) else {
            return
        }
        Task {
            do {
                try await service.updatePendingReviewComment(commentNodeID: nodeID, body: body)
            } catch {
                updateSession(target, generation: generation) { session in
                    if let previousBody {
                        session.detail?.updateThreadCommentBody(nodeID: nodeID, body: previousBody)
                    }
                    session.composerAnchor = anchor
                    session.composerText = body
                    session.composerPendingCommentNodeID = nodeID
                    session.composerError = error.localizedDescription
                    session.composerFocusToken = UUID()
                    composerDraft = PullRequestCommentDraftBox(markdown: body)
                }
            }
        }
    }

    // MARK: - Delete

    /// Deletes one of the viewer's unsubmitted comments. No confirmation dialog:
    /// nothing is published yet, and github.com deletes pending comments outright
    /// too. Removing the last one discards the now-empty pending review.
    func deletePendingComment(nodeID: String) {
        guard let target = activePaneTarget, let session = paneSessions[target] else {
            return
        }
        let generation = session.generation
        var removed: PullRequestDetail.RemovedThreadComment?
        guard updateSession(target, generation: generation, { session in
            removed = session.detail?.removeThreadComment(nodeID: nodeID)
            if session.composerPendingCommentNodeID == nodeID {
                session.composerAnchor = nil
                session.composerText = ""
                session.composerPendingCommentNodeID = nil
                composerDraft = nil
            }
            session.composerError = nil
        }), removed != nil else {
            return
        }
        Task {
            do {
                try await service.deletePendingReviewComment(commentNodeID: nodeID)
                await discardPendingReviewIfEmpty(target: target, generation: generation)
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

    /// Keeps github.com clean: an empty pending review would otherwise linger as a
    /// "pending" badge with nothing in it.
    private func discardPendingReviewIfEmpty(
        target: PullRequestPaneTarget,
        generation: UUID
    ) async {
        guard let session = paneSessions[target],
              session.generation == generation,
              let detail = session.detail,
              let reviewNodeID = detail.pendingReviewNodeID,
              detail.pendingCommentCount == 0 else {
            return
        }
        // Drop the id *before* the round trip. A comment written while the delete
        // is in flight would otherwise be attached to a review GitHub is about to
        // destroy and fail with a 422; with the id already gone it opens a fresh
        // pending review instead. A failed delete puts the id back, because
        // GitHub refuses a second pending review while that one still exists.
        updateSession(target, generation: generation) { session in
            session.detail?.pendingReviewNodeID = nil
        }
        do {
            try await service.deletePendingReview(reviewNodeID: reviewNodeID)
        } catch {
            // The comment itself did delete, so this is a cosmetic remainder on
            // GitHub rather than a failure worth a banner — but the id has to
            // come back or the next comment tries to open a duplicate review.
            updateSession(target, generation: generation) { session in
                if session.detail?.pendingReviewNodeID == nil {
                    session.detail?.pendingReviewNodeID = reviewNodeID
                }
            }
        }
    }
}

/// One in-flight "add a pending comment" attempt: what the retry-on-failure path
/// needs to withdraw the placeholder and put the text back in the composer.
private struct PendingCommentCreation: Equatable, Sendable {
    let pullRequestNodeID: String
    /// The optimistic thread's local node id, replaced by GitHub's on success.
    let placeholderID: String
    let anchor: DiffCommentAnchor
    let body: String
}
