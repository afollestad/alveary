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
        selectedCommitIDs.insert(commit.id)
        if commitSelectionAnchorID == nil {
            commitSelectionAnchorID = commit.id
        }
        commitDiffFiles = []
        commitImagePreviews = [:]
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

    func selectCommit(
        _ commit: CommitInfo,
        behavior: DiffViewerCommitSelectionBehavior = .single
    ) async {
        guard let preparedSelection = selectCommitImmediately(commit, behavior: behavior) else {
            return
        }

        await loadSelectedCommitDiff(preparedSelection)
    }

    func selectCommitImmediately(
        _ commit: CommitInfo,
        behavior: DiffViewerCommitSelectionBehavior = .single
    ) -> DiffViewerPreparedCommitSelection? {
        guard let target = diffStore.activeTarget else {
            clearCommitState()
            return nil
        }

        guard let previewCommit = applyCommitSelection(commit, behavior: behavior) else {
            clearSelectedCommitDiffState()
            return nil
        }

        guard selectedCommit?.id != previewCommit.id
                || commitDiffFiles.isEmpty && rawCommitDiffContent.isEmpty && selectedCommitDiffLoadState != .loading else {
            return nil
        }

        return DiffViewerPreparedCommitSelection(commit: previewCommit, target: target)
    }

    func selectAllCommitsImmediately() -> DiffViewerPreparedCommitSelection? {
        guard let target = diffStore.activeTarget else {
            clearCommitState()
            return nil
        }
        guard !aheadCommits.isEmpty else {
            return nil
        }

        selectedCommitIDs = Set(aheadCommits.map(\.id))
        let previewCommit = selectedCommit.flatMap(commit(matching:)) ?? aheadCommits.first
        commitSelectionAnchorID = commitSelectionAnchorID.flatMap { selectedCommitIDs.contains($0) ? $0 : nil }
            ?? previewCommit?.id

        guard let previewCommit,
              selectedCommit?.id != previewCommit.id
                || commitDiffFiles.isEmpty && rawCommitDiffContent.isEmpty && selectedCommitDiffLoadState != .loading else {
            return nil
        }

        return DiffViewerPreparedCommitSelection(commit: previewCommit, target: target)
    }

    func selectAllCommits() async {
        guard let preparedSelection = selectAllCommitsImmediately() else {
            return
        }

        await loadSelectedCommitDiff(preparedSelection)
    }

    func loadSelectedCommitDiff(_ preparedSelection: DiffViewerPreparedCommitSelection) async {
        guard diffStore.activeTarget == preparedSelection.target else {
            return
        }

        await loadCommitDiff(for: preparedSelection.commit, target: preparedSelection.target)
    }

    func isCommitSelected(_ commit: CommitInfo) -> Bool {
        selectedCommitIDs.contains(commit.id)
    }

    func clearCommitState() {
        commitGeneration &+= 1
        cancelCommitLoads()
        pendingCommitReloadTarget = nil
        commitListTarget = nil
        isCommitListRefreshNeeded = false
        aheadCommits = []
        selectedCommit = nil
        selectedCommitIDs = []
        commitSelectionAnchorID = nil
        commitDiffFiles = []
        commitImagePreviews = [:]
        rawCommitDiffContent = ""
        selectedCommitDiffErrorMessage = nil
        commitsLoadState = .idle
        selectedCommitDiffLoadState = .idle
        collapsedCommitFileIDsByCommitHash = [:]
    }

    func beginCommitListLoad(preservesSelectedDiff: Bool) {
        commitsLoadState = .loading
        if !preservesSelectedDiff {
            aheadCommits = []
            selectedCommitDiffLoadState = .idle
            selectedCommit = nil
            selectedCommitIDs = []
            commitSelectionAnchorID = nil
            commitDiffFiles = []
            commitImagePreviews = [:]
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

        let previousSelectedCommitIDs = selectedCommitIDs
        aheadCommits = commits
        reconcileCommitSelection(previousSelectedCommitIDs: previousSelectedCommitIDs)
        pruneCollapsedCommitFileState(availableCommits: commits)
        commitsLoadState = .loaded
        inFlightCommitListLoad = nil
        let selectedCommitHash = selectedCommit?.hash
        let remainingSelectedCommit = commits.first { selectedCommitIDs.contains($0.id) }
        let commitToLoad = commits.first(where: { $0.hash == selectedCommitHash })
            ?? commits.first(where: { $0.hash == context.preferredCommitHash })
            ?? remainingSelectedCommit
            ?? commits.first
        guard let commitToLoad else {
            clearSelectedCommitDiffState()
            return
        }
        if selectedCommitIDs.isEmpty {
            selectedCommitIDs = [commitToLoad.id]
            commitSelectionAnchorID = commitToLoad.id
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
        selectedCommitIDs = []
        commitSelectionAnchorID = nil
        commitDiffFiles = []
        commitImagePreviews = [:]
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
        commitImagePreviews = result.imagePreviews
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
        commitImagePreviews = [:]
        selectedCommitDiffErrorMessage = error.localizedDescription
        selectedCommitDiffLoadState = .failed
        inFlightCommitDiffLoad = nil
        diffStore.presentGitError("Commit diff failed: \(error.localizedDescription)")
    }

    func pruneCollapsedCommitFileState(availableCommits: [CommitInfo]) {
        let availableHashes = Set(availableCommits.map(\.hash))
        collapsedCommitFileIDsByCommitHash = collapsedCommitFileIDsByCommitHash.filter { availableHashes.contains($0.key) }
    }

    func applyCommitSelection(
        _ commit: CommitInfo,
        behavior: DiffViewerCommitSelectionBehavior
    ) -> CommitInfo? {
        let commitID = commit.id
        let clickedIndex = aheadCommits.firstIndex { $0.id == commitID }

        switch behavior {
        case .single:
            selectedCommitIDs = [commitID]
            commitSelectionAnchorID = commitID
            return commit

        case .toggle:
            if selectedCommitIDs.contains(commitID) {
                selectedCommitIDs.remove(commitID)
                commitSelectionAnchorID = commitID

                guard selectedCommit?.id == commitID else {
                    return selectedCommit
                }
                return nearestSelectedCommit(to: clickedIndex)
            } else {
                selectedCommitIDs.insert(commitID)
                commitSelectionAnchorID = commitID
                return commit
            }

        case .range:
            selectedCommitIDs = commitSelectionRangeIDs(to: commitID)
            return commit

        case .rangeUnion:
            selectedCommitIDs.formUnion(commitSelectionRangeIDs(to: commitID))
            return commit
        }
    }

    func reconcileCommitSelection(previousSelectedCommitIDs: Set<String>) {
        let availableIDs = Set(aheadCommits.map(\.id))
        selectedCommitIDs = previousSelectedCommitIDs.intersection(availableIDs)

        if let commitSelectionAnchorID,
           !availableIDs.contains(commitSelectionAnchorID) {
            self.commitSelectionAnchorID = aheadCommits.first { selectedCommitIDs.contains($0.id) }?.id
        }
    }

    func commit(matching selectedCommit: CommitInfo) -> CommitInfo? {
        aheadCommits.first { $0.id == selectedCommit.id }
    }

    func commitSelectionRangeIDs(to commitID: String) -> Set<String> {
        let anchorID = commitSelectionAnchorID ?? commitID
        if commitSelectionAnchorID == nil {
            commitSelectionAnchorID = anchorID
        }

        guard let anchorIndex = aheadCommits.firstIndex(where: { $0.id == anchorID }),
              let clickedIndex = aheadCommits.firstIndex(where: { $0.id == commitID }) else {
            commitSelectionAnchorID = commitID
            return [commitID]
        }

        let range = min(anchorIndex, clickedIndex)...max(anchorIndex, clickedIndex)
        return Set(aheadCommits[range].map(\.id))
    }

    func nearestSelectedCommit(to index: Int?) -> CommitInfo? {
        let selectedIDs = selectedCommitIDs
        guard !selectedIDs.isEmpty else {
            return nil
        }
        guard let index else {
            return aheadCommits.first { selectedIDs.contains($0.id) }
        }

        let orderedDistances = aheadCommits.indices
            .filter { selectedIDs.contains(aheadCommits[$0].id) }
            .map { (index: $0, distance: abs($0 - index)) }
            .sorted {
                if $0.distance == $1.distance {
                    return $0.index < $1.index
                }
                return $0.distance < $1.distance
            }

        guard let nearestIndex = orderedDistances.first?.index else {
            return nil
        }
        return aheadCommits[nearestIndex]
    }
}
