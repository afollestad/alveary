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
    /// The list row the pane was opened from, for the window where the detail has not landed yet.
    /// Between the two, linking a spawned thread never needs the network.
    let knownSummary: PullRequestSummary?
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

    func clearAgenticThreadMissingProject() {
        mutateActiveSession { session in
            session.agenticThreadMissingProject = nil
        }
    }

    /// Spawns the agentic thread and marks its route working, without moving the user anywhere.
    ///
    /// Navigation used to fire here the moment the thread existed, which threw away the pull
    /// request the user was reading — and unmounted the Overview a beat before the link landed in
    /// it, so the Linked threads row nobody ever saw was the one pointing at the new thread. The
    /// footer's own button carries the state instead: it spins and goes dead for its route until
    /// that thread's first turn ends, and the Linked threads row is the way in.
    ///
    /// Per kind, so a running review does not block addressing feedback. Two runs on one pull
    /// request are fine; two runs on one *route* are what the tracker's guard refuses.
    func startAgenticThread(kind: PullRequestAgenticThreadService.Kind) {
        guard let target = activePaneTarget,
              let session = paneSessions[target],
              !agenticThreadActivity.isWorking(target.identifier, kind: kind),
              let agenticThreadStarter,
              let request = agenticThreadRequest(kind: kind, target: target, session: session) else {
            return
        }
        let generation = session.generation
        let identifier = target.identifier
        updateSession(target, generation: generation) { session in
            session.agenticThreadError = nil
            session.agenticThreadMissingProject = nil
        }
        // Ahead of the `Task`, so the button is spinning on the click's own turn rather than after
        // the first suspension — and so the guard above refuses a second click immediately.
        agenticThreadActivity.begin(identifier, kind: kind)
        Task {
            let start: PullRequestAgenticThreadStart
            do {
                start = try await agenticThreadStarter(request)
            } catch {
                agenticThreadActivity.end(identifier, kind: kind)
                applyAgenticThreadStartFailure(error, target: target, generation: generation)
                return
            }
            agenticThreadActivity.attach(
                conversationID: start.conversationID,
                identifier: identifier,
                kind: kind
            )
            do {
                let outcome = try await start.dispatch.value
                // The prompt is out, so a turn is owed; the grace bounds how long it may take to
                // appear before the route stops claiming to be working.
                agenticThreadActivity.armStartupGrace(identifier, kind: kind)
                if let linkFailure = outcome.linkFailure {
                    presentToast(linkFailure)
                }
            } catch {
                // A throw means the prompt never went out, so nothing will ever report a turn for
                // this thread — the route has to stop working now or it would spin forever.
                agenticThreadActivity.end(identifier, kind: kind)
                presentToast(error.localizedDescription)
            }
        }
    }

    /// A failure from before the thread existed, which the still-mounted footer can show. The
    /// missing-project refusal is the one the user can act on, and the action lives outside this
    /// pane, so it gets the modal; everything else is the inline banner.
    private func applyAgenticThreadStartFailure(
        _ error: Error,
        target: PullRequestPaneTarget,
        generation: UUID
    ) {
        if case PullRequestAgenticThreadService.StartError.projectMissing(let repository) = error {
            updateSession(target, generation: generation) { session in
                session.agenticThreadMissingProject = repository
            }
            return
        }
        updateSession(target, generation: generation) { session in
            session.agenticThreadError = error.localizedDescription
        }
    }

    /// Observed synchronously (`queue: nil`) so a transition lands on the pane session inside the
    /// tracker's own `post` — which is what puts the spinner up on the click's turn.
    func observeAgenticThreadActivity() {
        agenticThreadActivityObserver = notificationCenter.addObserver(
            forName: .pullRequestAgenticThreadActivityChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.mirrorAgenticThreadActivity()
            }
        }
    }

    func endAgenticThreadActivityObservation() {
        if let agenticThreadActivityObserver {
            notificationCenter.removeObserver(agenticThreadActivityObserver)
            self.agenticThreadActivityObserver = nil
        }
    }

    /// Mirrors the app-scoped tracker onto every session it touches. Through `mutateSession` and
    /// not `updateSession(_:generation:_:)`: this reacts to a notification rather than resuming
    /// after an `await`, so it holds no generation, and the write belongs to whatever session the
    /// target currently has — retained ones included, since one of them may be remounted next.
    private func mirrorAgenticThreadActivity() {
        // Snapshotted: the loop writes back into the dictionary it is walking.
        for target in Array(paneSessions.keys) {
            let working = agenticThreadActivity.workingKinds(for: target.identifier)
            guard paneSessions[target]?.workingAgenticKinds != working else {
                continue
            }
            mutateSession(target) { session in
                session.workingAgenticKinds = working
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
            // And the row it was opened from covers the window before that detail lands, so the
            // link never has to reach GitHub to know what it is storing.
            knownSummary: session.summary,
            preferredProjectID: activePaneProjectID
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
