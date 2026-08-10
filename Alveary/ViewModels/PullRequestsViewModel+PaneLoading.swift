import Foundation

// MARK: - Pane loading

/// Fetching and cancellation for an open pane's detail and diff.
///
/// Every write here goes through `updateSession(_:generation:_:)` rather than
/// touching `paneSessions` directly, because that setter is file-private to the
/// view model — the generation guard it applies is the same one these loads need.
extension PullRequestsViewModel {
    func loadPaneContent(target: PullRequestPaneTarget, generation: UUID) {
        startDetailLoad(target: target, generation: generation)
        startDiffLoad(target: target, generation: generation)
    }

    /// Restarts whichever legs a cancellation left unfinished. A completed leg stays
    /// cached — reopening it is instant — and a failed one keeps its banner, so only
    /// a load that was interrupted mid-flight is issued again.
    func resumeIncompleteLoads(target: PullRequestPaneTarget, generation: UUID) {
        guard let session = paneSessions[target] else {
            return
        }
        let tasks = paneLoadTasks[target]
        if tasks?.detail == nil, session.detail == nil, session.detailError == nil {
            startDetailLoad(target: target, generation: generation)
        }
        if tasks?.diff == nil, session.diffFiles == nil, session.diffState == .loading {
            startDiffLoad(target: target, generation: generation)
        }
    }

    /// Re-runs a detail fetch that failed. Separate from `resumeIncompleteLoads`,
    /// which deliberately leaves a failed leg alone: only an explicit user action
    /// should retry, or a pull request that reliably 404s would refetch on every
    /// reopen. Clearing the error before starting restores the spinner.
    func retryDetailLoad() {
        guard let target = activePaneTarget,
              let session = paneSessions[target],
              session.detailError != nil,
              paneLoadTasks[target]?.detail == nil else {
            return
        }
        let generation = session.generation
        updateSession(target, generation: generation) { session in
            session.detailError = nil
            session.isLoadingDetail = true
        }
        startDetailLoad(target: target, generation: generation)
    }

    /// Re-runs a diff fetch that failed. `.tooLarge` is deliberately not retryable —
    /// the response exceeded a fixed cap, so a second identical request cannot help.
    func retryDiffLoad() {
        guard let target = activePaneTarget,
              let generation = paneSessions[target]?.generation,
              paneLoadTasks[target]?.diff == nil,
              case .failed = paneSessions[target]?.diffState else {
            return
        }
        updateSession(target, generation: generation) { session in
            session.diffState = .loading
        }
        startDiffLoad(target: target, generation: generation)
    }

    /// Cancels every pane's loads except the one named, enforcing the
    /// at-most-one-live-pane invariant directly rather than through
    /// `activePaneTarget` — a route-only `deactivatePane()` clears the active target
    /// while deliberately leaving its loads running, so keying off it would let two
    /// panes overlap.
    func cancelPaneLoads(except target: PullRequestPaneTarget) {
        for (loadedTarget, tasks) in paneLoadTasks where loadedTarget != target {
            tasks.cancelAll()
            paneLoadTasks[loadedTarget] = nil
        }
    }

    func cancelPaneLoads(for target: PullRequestPaneTarget) {
        guard let tasks = paneLoadTasks.removeValue(forKey: target) else {
            return
        }
        tasks.cancelAll()
    }

    /// Refetches a session's detail after something outside the pane changed the pull request —
    /// see `PullRequestsViewModel+RemoteChanges.swift`.
    ///
    /// Registered like every other pane load rather than awaited inline the way the pane's own
    /// mutations are: this can fire for a *retained* session the user routed away from, which is
    /// exactly what `cancelPaneLoads(except:)` bounds. A load already in flight is therefore also
    /// the dedupe — it is at most one debounce old, so it already carries the change.
    ///
    /// Unlike `retryDetailLoad()` this refetches a leg that previously failed: that rule guards
    /// passive reopens, not data known to have just moved.
    func refreshDetailAfterRemoteChange(target: PullRequestPaneTarget) {
        guard let generation = paneSessions[target]?.generation,
              paneLoadTasks[target]?.detail == nil else {
            return
        }
        updateSession(target, generation: generation) { session in
            session.isLoadingDetail = true
        }
        startDetailLoad(target: target, generation: generation, reportsFailure: false)
    }

    private func startDetailLoad(
        target: PullRequestPaneTarget,
        generation: UUID,
        reportsFailure: Bool = true
    ) {
        let token = UUID()
        let task = Task {
            await loadDetail(target: target, generation: generation, reportsFailure: reportsFailure)
            finishLoad(target: target, keyPath: \.detail, token: token)
        }
        paneLoadTasks[target, default: PullRequestPaneLoadTasks()].detail =
            PullRequestPaneLoad(token: token, task: task)
    }

    private func startDiffLoad(target: PullRequestPaneTarget, generation: UUID) {
        let token = UUID()
        let task = Task {
            await loadDiff(target: target, generation: generation)
            finishLoad(target: target, keyPath: \.diff, token: token)
        }
        paneLoadTasks[target, default: PullRequestPaneLoadTasks()].diff =
            PullRequestPaneLoad(token: token, task: task)
    }

    /// Clears a finished leg's handle, but only if it is still the one stored. A
    /// restart reuses the session's generation, so the token is the only thing that
    /// separates a cancelled load from its replacement — without this check the
    /// loser's cleanup would clear the winner's handle and let a later reopen start
    /// a duplicate fetch.
    private func finishLoad(
        target: PullRequestPaneTarget,
        keyPath: WritableKeyPath<PullRequestPaneLoadTasks, PullRequestPaneLoad?>,
        token: UUID
    ) {
        guard var tasks = paneLoadTasks[target],
              tasks[keyPath: keyPath]?.token == token else {
            return
        }
        tasks[keyPath: keyPath] = nil
        paneLoadTasks[target] = tasks.isEmpty ? nil : tasks
    }

    /// `onFinish` mutates the session in the same write that applies the load's
    /// outcome, so callers can swap dependent state (e.g. the pending review batch
    /// after submission) without an intermediate frame where both are absent.
    ///
    /// `reportsFailure: false` is for a refetch nobody asked for: the session keeps
    /// whatever detail it already had, and the Overview's banner — written for a
    /// first load with nothing to show, so it offers no dismiss — must not appear
    /// over it because a background refresh met a flaky network.
    func loadDetail(
        target: PullRequestPaneTarget,
        generation: UUID,
        reportsFailure: Bool = true,
        onFinish: ((inout PullRequestPaneSession) -> Void)? = nil
    ) async {
        do {
            let detail = try await service.fetchDetail(target.identifier)
            // The pane's comment ages are measured against this; without a touch they
            // would read relative to whenever the list last refreshed.
            touchReferenceDate()
            updateSession(target, generation: generation) { session in
                session.detail = detail
                session.detailError = nil
                session.isLoadingDetail = false
                if session.summary == nil {
                    // An identifier-opened pane has no snapshot; the detail it just
                    // fetched is what one would have been derived from anyway.
                    session.summary = PullRequestLinkService.makeSummary(from: detail)
                }
                onFinish?(&session)
            }
        } catch {
            // Shell teardown wraps cancellation in a service error, so the thrown type
            // cannot be trusted. Leaving the session untouched is also what lets
            // `resumeIncompleteLoads` read it as interrupted rather than failed.
            guard !Task.isCancelled else {
                return
            }
            updateSession(target, generation: generation) { session in
                if reportsFailure {
                    session.detailError = error.localizedDescription
                }
                session.isLoadingDetail = false
                onFinish?(&session)
            }
        }
    }

    private func loadDiff(target: PullRequestPaneTarget, generation: UUID) async {
        do {
            let raw = try await service.fetchDiff(target.identifier)
            let parsed = await Task.detached(priority: .userInitiated) {
                DiffParser.parse(raw)
            }.value
            updateSession(target, generation: generation) { session in
                session.diffFiles = parsed
                session.diffState = .loaded
                session.collapsedDiffFileIDs = PullRequestDiffFilePaging.autoCollapsedFileIDs(for: parsed)
            }
        } catch {
            guard !Task.isCancelled else {
                return
            }
            updateSession(target, generation: generation) { session in
                if case PullRequestsServiceError.responseTooLarge = error {
                    session.diffState = .tooLarge
                } else {
                    session.diffState = .failed(error.localizedDescription)
                }
            }
        }
    }
}
