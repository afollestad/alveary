import Foundation

// State changes to the pull request itself — close, reopen, and both draft
// directions — driven by the review footer's state button.
extension PullRequestsViewModel {
    /// Closes or reopens the active pane's pull request.
    func setPullRequestClosed(_ closed: Bool) {
        performStateChange(optimisticStatus: closed ? .closed : .open) { service, target in
            try await service.setPullRequestClosed(target.identifier, closed: closed)
        }
    }

    /// Takes the active pane's draft pull request out of draft. The node id is
    /// resolved up front: without it there is no mutation to run, and entering
    /// the shared path anyway would apply the optimistic status for nothing.
    func markPullRequestReadyForReview() {
        guard let nodeID = activePaneSession?.detail?.nodeID else {
            return
        }
        performStateChange(optimisticStatus: .open) { service, _ in
            try await service.markPullRequestReadyForReview(nodeID: nodeID)
        }
    }

    /// Puts the active pane's open pull request back into draft. The node id is
    /// resolved up front for the same reason as its inverse.
    func convertPullRequestToDraft() {
        guard let nodeID = activePaneSession?.detail?.nodeID else {
            return
        }
        performStateChange(optimisticStatus: .draft) { service, _ in
            try await service.convertPullRequestToDraft(nodeID: nodeID)
        }
    }

    func clearPullRequestStateChangeError() {
        mutateActiveSession { session in
            session.stateChangeError = nil
        }
    }

    /// The shared shape of every state change: guard re-entry, run the mutation,
    /// apply the expected status to the pane and its list row, then refetch the
    /// detail so GitHub's own timeline row (closed / reopened / ready for review)
    /// lands in the Overview. The refetched status also corrects the optimistic
    /// one — a reopened draft comes back as `.draft`, not `.open`.
    private func performStateChange(
        optimisticStatus: PullRequestStatus,
        mutate: @escaping (any PullRequestsService, PullRequestPaneTarget) async throws -> Void
    ) {
        guard let target = activePaneTarget,
              let session = paneSessions[target],
              !session.isChangingState else {
            return
        }
        let generation = session.generation
        updateSession(target, generation: generation) { session in
            session.stateChangeError = nil
            session.isChangingState = true
        }
        Task {
            do {
                try await mutate(service, target)
                applyStatus(optimisticStatus, to: target, generation: generation)
                guard updateSession(target, generation: generation, { session in
                    session.isLoadingDetail = true
                }) else {
                    return
                }
                await loadDetail(target: target, generation: generation) { session in
                    session.isChangingState = false
                    if let status = session.detail?.status {
                        session.summary.status = status
                    }
                }
                if let settled = paneSessions[target]?.summary.status {
                    applyStatus(settled, toRow: target.identifier)
                }
            } catch {
                updateSession(target, generation: generation) { session in
                    session.stateChangeError = error.localizedDescription
                    session.isChangingState = false
                }
            }
        }
    }

    /// Keeps the pane's own summary and its list row in step without a full list
    /// refresh; the next fetch confirms both.
    private func applyStatus(
        _ status: PullRequestStatus,
        to target: PullRequestPaneTarget,
        generation: UUID
    ) {
        updateSession(target, generation: generation) { session in
            session.summary.status = status
        }
        applyStatus(status, toRow: target.identifier)
    }
}
