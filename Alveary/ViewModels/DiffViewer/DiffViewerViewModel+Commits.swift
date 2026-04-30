import Foundation

@MainActor
extension DiffViewerViewModel {
    func loadAheadCommits(for target: DiffWorkspaceTarget) async {
        commitGeneration &+= 1
        let generation = commitGeneration
        cancelCommitLoads()
        commitsLoadState = .loading
        selectedCommitDiffLoadState = .idle
        aheadCommits = []
        selectedCommit = nil
        commitDiffFiles = []
        rawCommitDiffContent = ""
        selectedCommitDiffErrorMessage = nil

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
            guard matchesCurrentCommitLoad(target: target, generation: generation, listLoadID: loadID) else {
                return
            }

            aheadCommits = commits
            commitsLoadState = .loaded
            inFlightCommitListLoad = nil
            if let firstCommit = commits.first {
                await loadCommitDiff(for: firstCommit, target: target)
            }
        } catch is CancellationError {
            finishCommitListLoadIfCurrent(target: target, generation: generation, loadID: loadID, state: .idle)
        } catch {
            applyCommitListError(error, target: target, generation: generation, loadID: loadID)
        }
    }

    func loadCommitDiff(for commit: CommitInfo, target: DiffWorkspaceTarget) async {
        commitGeneration &+= 1
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
    }

    func clearCommitState() {
        commitGeneration &+= 1
        cancelCommitLoads()
        aheadCommits = []
        selectedCommit = nil
        commitDiffFiles = []
        rawCommitDiffContent = ""
        selectedCommitDiffErrorMessage = nil
        commitsLoadState = .idle
        selectedCommitDiffLoadState = .idle
    }

    func cancelCommitLoads() {
        inFlightCommitListLoad?.task.cancel()
        inFlightCommitListLoad = nil
        cancelCommitDiffLoad()
    }

    func cancelCommitDiffLoad() {
        inFlightCommitDiffLoad?.task.cancel()
        inFlightCommitDiffLoad = nil
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
