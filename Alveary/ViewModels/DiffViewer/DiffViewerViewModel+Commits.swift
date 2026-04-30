import Foundation

struct CommitListResultContext {
    let target: DiffWorkspaceTarget
    let generation: UInt64
    let loadID: UUID
    let preferredCommitHash: String?
    let preservesSelectedDiff: Bool
}

@MainActor
extension DiffViewerViewModel {
    func loadAheadCommits(
        for target: DiffWorkspaceTarget,
        preservesSelectedDiff: Bool = false,
        forceReload: Bool = false
    ) async {
        guard inFlightCommitListLoad == nil,
              inFlightCommitDiffLoad == nil else {
            if forceReload {
                // Workspace refreshes can arrive while a commit diff is loading; coalesce
                // them so the visible diff task can publish instead of being restarted.
                pendingCommitReloadTarget = target
            }
            return
        }

        guard forceReload || commitListTarget != target || commitsLoadState != .loaded else {
            return
        }

        commitGeneration &+= 1
        let generation = commitGeneration
        cancelCommitLoads()
        pendingCommitReloadTarget = nil
        commitListTarget = target
        isCommitListRefreshNeeded = false
        let preferredCommitHash = selectedCommit?.hash
        beginCommitListLoad(preservesSelectedDiff: preservesSelectedDiff)

        let gitService = gitService
        let task = Task.detached(priority: .userInitiated) {
            try await gitService.commitsAheadOfBaseDetails(
                baseBranch: target.baseRef,
                remoteName: target.remoteName,
                in: target.directory
            )
        }
        let loadID = UUID()
        inFlightCommitListLoad = (id: loadID, task: task)

        do {
            let commits = try await task.value
            await applyCommitListResult(
                commits,
                context: CommitListResultContext(
                    target: target,
                    generation: generation,
                    loadID: loadID,
                    preferredCommitHash: preferredCommitHash,
                    preservesSelectedDiff: preservesSelectedDiff
                )
            )
            await runPendingCommitReloadIfNeeded(after: target)
        } catch is CancellationError {
            finishCommitListLoadIfCurrent(target: target, generation: generation, loadID: loadID, state: .idle)
            await runPendingCommitReloadIfNeeded(after: target)
        } catch {
            applyCommitListError(error, target: target, generation: generation, loadID: loadID)
            await runPendingCommitReloadIfNeeded(after: target)
        }
    }

    func loadCommitDiff(
        for commit: CommitInfo,
        target: DiffWorkspaceTarget,
        processesPendingReload: Bool = true
    ) async {
        // Keep manual commit selection from invalidating an in-flight list reload; diff
        // staleness is guarded by the selected hash and load id below.
        let generation = commitGeneration
        cancelCommitDiffLoad()
        selectedCommit = commit
        commitDiffFiles = []
        rawCommitDiffContent = ""
        selectedCommitDiffErrorMessage = nil
        selectedCommitDiffLoadState = .loading

        let task = DiffViewerCommitDiffTaskFactory.makeTask(for: commit, in: target.directory, gitService: gitService)
        let loadID = UUID()
        inFlightCommitDiffLoad = (id: loadID, task: task)

        do {
            let result = try await task.value
            applyCommitDiffResult(result, commit: commit, target: target, generation: generation, loadID: loadID)
        } catch is CancellationError {
            finishCommitDiffLoadIfCurrent(target: target, generation: generation, loadID: loadID, state: .idle)
        } catch {
            applyCommitDiffError(error, commit: commit, target: target, generation: generation, loadID: loadID)
        }

        if processesPendingReload {
            await runPendingCommitReloadIfNeeded(after: target)
        }
    }

    func clearCommitState() {
        commitGeneration &+= 1
        cancelCommitLoads()
        pendingCommitReloadTarget = nil
        commitListTarget = nil
        isCommitListRefreshNeeded = false
        aheadCommits = []
        selectedCommit = nil
        commitDiffFiles = []
        rawCommitDiffContent = ""
        selectedCommitDiffErrorMessage = nil
        commitsLoadState = .idle
        selectedCommitDiffLoadState = .idle
    }

    func beginCommitListLoad(preservesSelectedDiff: Bool) {
        commitsLoadState = .loading
        if !preservesSelectedDiff {
            aheadCommits = []
            selectedCommitDiffLoadState = .idle
            selectedCommit = nil
            commitDiffFiles = []
            rawCommitDiffContent = ""
            selectedCommitDiffErrorMessage = nil
        }
    }

    func applyCommitListResult(
        _ commits: [CommitInfo],
        context: CommitListResultContext
    ) async {
        guard matchesCurrentCommitLoad(target: context.target, generation: context.generation, listLoadID: context.loadID) else {
            return
        }

        aheadCommits = commits
        commitsLoadState = .loaded
        inFlightCommitListLoad = nil
        let selectedCommitHash = selectedCommit?.hash
        let commitToLoad = commits.first(where: { $0.hash == selectedCommitHash })
            ?? commits.first(where: { $0.hash == context.preferredCommitHash })
            ?? commits.first
        guard let commitToLoad else {
            clearSelectedCommitDiffState()
            return
        }

        if context.preservesSelectedDiff,
           selectedCommit?.hash == commitToLoad.hash,
           selectedCommitDiffLoadState == .loaded || selectedCommitDiffLoadState == .loading {
            selectedCommit = commitToLoad
        } else {
            await loadCommitDiff(for: commitToLoad, target: context.target, processesPendingReload: false)
        }
    }

    func cancelCommitLoads() {
        inFlightCommitListLoad?.task.cancel()
        inFlightCommitListLoad = nil
        cancelCommitDiffLoad()
    }

    func runPendingCommitReloadIfNeeded(after target: DiffWorkspaceTarget) async {
        guard let pendingTarget = pendingCommitReloadTarget,
              isCommitModeActive,
              pendingTarget == target,
              diffStore.activeTarget == target,
              inFlightCommitListLoad == nil,
              inFlightCommitDiffLoad == nil else {
            return
        }

        pendingCommitReloadTarget = nil
        await loadAheadCommits(for: pendingTarget, preservesSelectedDiff: true, forceReload: true)
    }

    func cancelCommitDiffLoad() {
        inFlightCommitDiffLoad?.task.cancel()
        inFlightCommitDiffLoad = nil
    }

    func clearSelectedCommitDiffState() {
        selectedCommit = nil
        commitDiffFiles = []
        rawCommitDiffContent = ""
        selectedCommitDiffErrorMessage = nil
        selectedCommitDiffLoadState = .idle
    }

    func matchesCurrentCommitLoad(
        target: DiffWorkspaceTarget,
        generation: UInt64,
        listLoadID: UUID
    ) -> Bool {
        diffStore.activeTarget == target
            && commitGeneration == generation
            && inFlightCommitListLoad?.id == listLoadID
    }

    func matchesCurrentCommitDiffLoad(
        commit: CommitInfo,
        target: DiffWorkspaceTarget,
        generation: UInt64,
        loadID: UUID
    ) -> Bool {
        // Commit loads are target-scoped so stale async results from a previous project/worktree
        // cannot publish into the currently visible commits pane.
        return diffStore.activeTarget == target
            && commitGeneration == generation
            && selectedCommit?.hash == commit.hash
            && inFlightCommitDiffLoad?.id == loadID
    }

    func finishCommitListLoadIfCurrent(
        target: DiffWorkspaceTarget,
        generation: UInt64,
        loadID: UUID,
        state: DiffWorkspaceLoadState
    ) {
        guard matchesCurrentCommitLoad(target: target, generation: generation, listLoadID: loadID) else {
            return
        }
        commitsLoadState = state
        inFlightCommitListLoad = nil
    }

    func finishCommitDiffLoadIfCurrent(
        target: DiffWorkspaceTarget,
        generation: UInt64,
        loadID: UUID,
        state: DiffWorkspaceLoadState
    ) {
        guard diffStore.activeTarget == target,
              commitGeneration == generation,
              inFlightCommitDiffLoad?.id == loadID else {
            return
        }
        selectedCommitDiffLoadState = state
        inFlightCommitDiffLoad = nil
    }

    func applyCommitListError(
        _ error: Error,
        target: DiffWorkspaceTarget,
        generation: UInt64,
        loadID: UUID
    ) {
        guard matchesCurrentCommitLoad(target: target, generation: generation, listLoadID: loadID) else {
            return
        }
        commitsLoadState = .failed
        inFlightCommitListLoad = nil
        commitListTarget = target
        diffStore.presentGitError("Commit list failed: \(error.localizedDescription)")
    }

    func applyCommitDiffResult(
        _ result: DiffViewerCommitDiffLoadResult,
        commit: CommitInfo,
        target: DiffWorkspaceTarget,
        generation: UInt64,
        loadID: UUID
    ) {
        guard matchesCurrentCommitDiffLoad(commit: commit, target: target, generation: generation, loadID: loadID) else {
            return
        }
        rawCommitDiffContent = result.raw
        commitDiffFiles = result.parsed
        selectedCommitDiffErrorMessage = nil
        selectedCommitDiffLoadState = .loaded
        inFlightCommitDiffLoad = nil
    }

    func applyCommitDiffError(
        _ error: Error,
        commit: CommitInfo,
        target: DiffWorkspaceTarget,
        generation: UInt64,
        loadID: UUID
    ) {
        guard matchesCurrentCommitDiffLoad(commit: commit, target: target, generation: generation, loadID: loadID) else {
            return
        }
        rawCommitDiffContent = ""
        commitDiffFiles = []
        selectedCommitDiffErrorMessage = error.localizedDescription
        selectedCommitDiffLoadState = .failed
        inFlightCommitDiffLoad = nil
        diffStore.presentGitError("Commit diff failed: \(error.localizedDescription)")
    }
}
