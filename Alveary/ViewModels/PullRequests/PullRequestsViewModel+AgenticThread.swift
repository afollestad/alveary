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

    func openPullRequestReviewSettings() {
        openGitSettings()
    }

    /// Starts through the shared launcher, which owns activity across UI and host-tool callers.
    ///
    /// Navigation used to fire here the moment the thread existed, which threw away the pull
    /// request the user was reading — and unmounted the Overview a beat before the link landed in
    /// it, so the Linked threads row nobody ever saw was the one pointing at the new thread. The
    /// footer carries single-agent activity until the first turn ends, or team activity until the
    /// coordinator releases its route; the Linked threads row is the way in.
    ///
    /// Per kind, so a running review does not block addressing feedback. Two runs on one pull
    /// request are fine; two runs on one *route* are what the tracker's guard refuses.
    func startAgenticThread(kind: PullRequestAgenticThreadService.Kind) {
        guard let target = activePaneTarget,
              let session = paneSessions[target],
              Self.canStartAgenticThread(
                  kind: kind,
                  reviewMode: session.pullRequestReviewMode,
                  validationStatus: session.pullRequestReviewTeamValidationStatus
              ),
              !agenticThreadActivity.isWorking(target.identifier, kind: kind),
              let agenticThreadStarter,
              let request = agenticThreadRequest(kind: kind, target: target, session: session) else {
            return
        }
        let generation = session.generation
        updateSession(target, generation: generation) { session in
            session.agenticThreadError = nil
            session.agenticThreadMissingProject = nil
        }
        launchAgenticThread(request, starter: agenticThreadStarter) { error in
            self.applyAgenticThreadStartFailure(error, target: target, generation: generation)
        }
    }

    /// The list row menu's entry: starts a route without opening the pane. No footer is mounted to
    /// carry a pre-spawn failure, so it toasts — except a missing project, which raises the screen's
    /// alert for the reason the pane uses a modal: the fix lives elsewhere in the app.
    func startAgenticThread(kind: PullRequestAgenticThreadService.Kind, for summary: PullRequestSummary) {
        let identifier = summary.id
        guard !agenticThreadActivity.isWorking(identifier, kind: kind),
              let agenticThreadStarter,
              let url = summary.url ?? identifier.webURL else {
            return
        }
        guard Self.canStartAgenticThread(
            kind: kind,
            reviewMode: mirroredPullRequestReviewMode,
            validationStatus: mirroredReviewTeamValidationStatus
        ) else {
            if let message = mirroredReviewTeamValidationStatus.footerMessage {
                presentToast(message)
            }
            // Retries a failed or timed-out check, as opening a pane would.
            refreshPullRequestReviewConfigurationForPane()
            return
        }
        listAgenticThreadMissingProject = nil
        let request = PullRequestAgenticThreadRequest(
            kind: kind,
            identifier: identifier,
            url: url,
            // A retained pane session may already hold the detail, sparing the link a fetch.
            knownDetail: paneSessions[.details(identifier)]?.detail,
            knownSummary: summary,
            preferredProjectID: nil
        )
        launchAgenticThread(request, starter: agenticThreadStarter) { error in
            self.applyListAgenticThreadStartFailure(error)
        }
    }

    func clearListAgenticThreadMissingProject() {
        listAgenticThreadMissingProject = nil
    }

    /// Anything after the thread exists toasts from both entries: the deferred half can outlive
    /// the pane or screen that started it.
    private func launchAgenticThread(
        _ request: PullRequestAgenticThreadRequest,
        starter: @escaping @MainActor (PullRequestAgenticThreadRequest) async throws -> PullRequestAgenticThreadStart,
        onStartFailure: @escaping @MainActor (Error) -> Void
    ) {
        Task {
            let start: PullRequestAgenticThreadStart
            do {
                start = try await starter(request)
            } catch {
                onStartFailure(error)
                return
            }
            do {
                let outcome = try await start.dispatch.value
                if let linkFailure = outcome.linkFailure {
                    presentToast(linkFailure)
                }
            } catch {
                presentToast(error.localizedDescription)
            }
        }
    }

    /// Team review is the only agentic route whose saved configuration needs strict preflight.
    private static func canStartAgenticThread(
        kind: PullRequestAgenticThreadService.Kind,
        reviewMode: PullRequestReviewMode,
        validationStatus: PullRequestReviewTeamValidationStatus
    ) -> Bool {
        guard kind == .review, reviewMode == .reviewTeam else {
            return true
        }
        return validationStatus == .valid
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

    private func applyListAgenticThreadStartFailure(_ error: Error) {
        if case PullRequestAgenticThreadService.StartError.projectMissing(let repository) = error {
            listAgenticThreadMissingProject = repository
            return
        }
        presentToast(error.localizedDescription)
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
        refreshListWorkingAgenticKinds()
    }

    /// The same mirror for listed rows, which have no session. Looked up per listed identifier
    /// because the tracker normalizes repository casing, and equality-guarded so a transition on a
    /// pull request the list does not hold publishes nothing.
    func refreshListWorkingAgenticKinds() {
        var working: [PullRequestIdentifier: Set<PullRequestAgenticThreadService.Kind>] = [:]
        for identifier in items.map(\.id) {
            let kinds = agenticThreadActivity.workingKinds(for: identifier)
            if !kinds.isEmpty {
                working[identifier] = kinds
            }
        }
        if working != listWorkingAgenticKinds {
            listWorkingAgenticKinds = working
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
        guard let url = session.detail?.url ?? session.summary?.url ?? identifier.webURL else {
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
