import Foundation

// Actions on already-submitted review activity: thread resolution, review
// re-requests, and reactions. All apply optimistically and revert on failure;
// only the re-request refetches. Guarded writes go through the main file's
// `updateSession`.
extension PullRequestsViewModel {
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
}
