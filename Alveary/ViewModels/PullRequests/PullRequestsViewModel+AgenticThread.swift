import Foundation
import SwiftData

/// What the review footer's agentic options hand the spawn service. A struct rather than a wide
/// argument list, because every field but `kind` is context the footer resolves once and passes
/// straight through.
struct PullRequestAgenticThreadRequest {
    let kind: PullRequestAgenticThreadService.Kind
    let identifier: PullRequestIdentifier
    let url: URL
    /// The pane's already-fetched detail, so linking need not repeat the round trip.
    let knownDetail: PullRequestDetail?
    /// The project whose pane this is, preferred over the other clones holding the same
    /// repository when the address-feedback route has to cut a worktree.
    let preferredProjectID: PersistentIdentifier?
}

/// The review footer's split-button selection and the agentic options it can run.
extension PullRequestsViewModel {
    /// The stored pick for this pull request's authorship. A stored kind this build does not
    /// know falls back to that authorship's own default, so the footer always has a button.
    func selectedReviewFooterActionKind(
        for authorship: PullRequestReviewFooterAuthorship
    ) -> PullRequestReviewFooterAction.Kind {
        PullRequestReviewFooterAction.kind(
            fromStored: settingsService?.current[keyPath: Self.footerActionKindKeyPath(for: authorship)],
            default: authorship.defaultFooterActionKind
        )
    }

    /// Persists the caret's pick as the next launch's default for pull requests written by the
    /// same hand, matching how the screen's tab and filters persist. Selecting never runs the
    /// action.
    func selectReviewFooterAction(
        _ kind: PullRequestReviewFooterAction.Kind,
        for authorship: PullRequestReviewFooterAuthorship
    ) {
        guard selectedReviewFooterActionKind(for: authorship) != kind else {
            return
        }
        settingsService?.update { settings in
            settings[keyPath: Self.footerActionKindKeyPath(for: authorship)] = kind.rawValue
        }
    }

    /// One key path for both the read and the write, so the two cannot drift onto different keys.
    private static func footerActionKindKeyPath(
        for authorship: PullRequestReviewFooterAuthorship
    ) -> WritableKeyPath<AppSettings, String> {
        authorship == .authored ? \.pullRequestOwnFooterActionKind : \.pullRequestOthersFooterActionKind
    }

    func clearAgenticThreadError() {
        mutateActiveSession { session in
            session.agenticThreadError = nil
        }
    }

    /// Spawns the agentic thread and navigates to it as soon as it exists, then waits out the
    /// linking, any checkout, and the first prompt behind that navigation. Navigation unmounts
    /// this pane — it is origin-scoped — so every write is generation-guarded; a completion that
    /// lands after the session is gone applies nothing, which is why the deferred half reports
    /// through the app-level toast instead of the footer's banner.
    ///
    /// Both kinds share the busy flag and the banner: the footer runs one at a time, and starting
    /// either while the other is spawning would put two threads on one pull request.
    func startAgenticThread(kind: PullRequestAgenticThreadService.Kind) {
        guard let target = activePaneTarget,
              let session = paneSessions[target],
              !session.isStartingAgenticThread,
              let agenticThreadStarter,
              let request = agenticThreadRequest(kind: kind, target: target, session: session) else {
            return
        }
        let generation = session.generation
        updateSession(target, generation: generation) { session in
            session.agenticThreadError = nil
            session.isStartingAgenticThread = true
        }
        Task {
            let start: PullRequestAgenticThreadStart
            do {
                start = try await agenticThreadStarter(request)
            } catch {
                updateSession(target, generation: generation) { session in
                    session.agenticThreadError = error.localizedDescription
                    session.isStartingAgenticThread = false
                }
                return
            }
            updateSession(target, generation: generation) { session in
                session.isStartingAgenticThread = false
            }
            requestThreadOpen(conversationID: start.conversationID)
            do {
                try await start.dispatch.value
            } catch {
                presentToast(error.localizedDescription)
            }
        }
    }

    /// Prefers the API-provided URL; the constructed fallback covers an identifier-opened pane
    /// whose detail has not landed, matching `PullRequestPane.pullRequestURL`.
    private func agenticThreadRequest(
        kind: PullRequestAgenticThreadService.Kind,
        target: PullRequestPaneTarget,
        session: PullRequestPaneSession
    ) -> PullRequestAgenticThreadRequest? {
        let identifier = target.identifier
        guard let url = session.detail?.url
            ?? session.summary?.url
            ?? URL(string: "https://github.com/\(identifier.nameWithOwner)/pull/\(identifier.number)") else {
            return nil
        }
        return PullRequestAgenticThreadRequest(
            kind: kind,
            identifier: identifier,
            url: url,
            // The pane already fetched this pull request; handing its detail over spares the link
            // an identical round trip, which is what keeps the new thread from sitting empty.
            knownDetail: session.detail,
            preferredProjectID: activePaneProjectID
        )
    }

    /// Selects the spawned thread. Sidebar selection is app-wide, so the request names only the
    /// conversation — see `ContentView+ThreadOpenRequests.swift`.
    private func requestThreadOpen(conversationID: String) {
        NotificationCenter.default.post(
            name: .threadOpenRequested,
            object: nil,
            userInfo: [
                ThreadOpenRequestNotificationKey.request: ThreadOpenRequest(conversationID: conversationID)
            ]
        )
    }

    /// A pane opened from a project names the clone the user is looking at; every other origin
    /// leaves the choice to the ladder.
    private var activePaneProjectID: PersistentIdentifier? {
        guard case .project(let id) = activePaneOrigin else {
            return nil
        }
        return id
    }
}
