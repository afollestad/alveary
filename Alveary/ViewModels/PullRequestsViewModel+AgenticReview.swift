import Foundation

/// The review footer's split-button selection and its agentic option.
extension PullRequestsViewModel {
    /// A stored kind this build does not know falls back to Submit review, so the footer
    /// always has a button.
    var selectedReviewFooterActionKind: PullRequestReviewFooterAction.Kind {
        PullRequestReviewFooterAction.kind(fromStored: settingsService?.current.pullRequestReviewFooterActionKind)
    }

    /// Persists the caret's pick as the next launch's default, matching how the screen's
    /// tab and filters persist. Selecting never runs the action.
    func selectReviewFooterAction(_ kind: PullRequestReviewFooterAction.Kind) {
        guard selectedReviewFooterActionKind != kind else {
            return
        }
        settingsService?.update { $0.pullRequestReviewFooterActionKind = kind.rawValue }
    }

    func clearAgenticReviewError() {
        mutateActiveSession { session in
            session.agenticReviewError = nil
        }
    }

    /// Spawns the review thread and navigates to it. Navigation unmounts this pane — it is
    /// origin-scoped — so every write is generation-guarded; a completion that lands after
    /// the session is gone applies nothing.
    func startAgenticReview() {
        guard let target = activePaneTarget,
              let session = paneSessions[target],
              !session.isStartingAgenticReview,
              let agenticReviewStarter else {
            return
        }
        // Prefer the API-provided URL; the constructed fallback covers an identifier-opened
        // pane whose detail has not landed, matching `PullRequestPane.pullRequestURL`.
        let identifier = target.identifier
        guard let url = session.detail?.url
            ?? session.summary?.url
            ?? URL(string: "https://github.com/\(identifier.nameWithOwner)/pull/\(identifier.number)") else {
            return
        }
        let generation = session.generation
        updateSession(target, generation: generation) { session in
            session.agenticReviewError = nil
            session.isStartingAgenticReview = true
        }
        Task {
            do {
                let conversationID = try await agenticReviewStarter(identifier, url)
                updateSession(target, generation: generation) { session in
                    session.isStartingAgenticReview = false
                }
                NotificationCenter.default.post(
                    name: .threadOpenRequested,
                    object: nil,
                    userInfo: [
                        ThreadOpenRequestNotificationKey.request: ThreadOpenRequest(conversationID: conversationID)
                    ]
                )
            } catch {
                updateSession(target, generation: generation) { session in
                    session.agenticReviewError = error.localizedDescription
                    session.isStartingAgenticReview = false
                }
            }
        }
    }
}
