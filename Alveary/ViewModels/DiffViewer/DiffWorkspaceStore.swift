import Foundation
import Observation

@MainActor
@Observable
final class DiffWorkspaceStore {
    private typealias DiffLoadResult = DiffViewerDiffLoadResult

    private let gitService: GitService
    let loadingIndicatorDelay: Duration

    private(set) var activeTarget: DiffWorkspaceTarget?
    private(set) var files: [FileStatus] = []
    private(set) var stats: DiffStats = .empty
    var statsLoadState: DiffWorkspaceLoadState = .idle
    var isStatsLoadingIndicatorVisible = false
    private(set) var selectedFile: FileStatus?
    var selectedFileKeys: Set<DiffViewerFileSelectionKey> = []
    private(set) var parsedDiff: DiffFile?
    private(set) var imagePreview: DiffImagePreview?
    private(set) var rawDiffContent = ""
    private(set) var selectedDiffErrorMessage: String?
    var selectedDiffLoadState: DiffWorkspaceLoadState = .idle
    var isSelectedDiffLoadingIndicatorVisible = false
    private(set) var isLoadingFiles = false
    private(set) var gitError: String?
    private(set) var isGitRepository = true

    private var targetGeneration: UInt64 = 0
    private var fileSelectionGeneration: UInt64 = 0
    var selectionAnchorKey: DiffViewerFileSelectionKey?
    var statsLoadingIndicatorGeneration: UInt64 = 0
    var selectedDiffLoadingIndicatorGeneration: UInt64 = 0
    private var statsCache: [DiffWorkspaceStatsCacheKey: DiffStats] = [:]
    private var inFlightStatsLoad: StatsLoad?
    private var inFlightDiffLoad: (id: UUID, task: Task<DiffLoadResult, Error>)?
    var statsLoadingIndicatorTask: Task<Void, Never>?
    var selectedDiffLoadingIndicatorTask: Task<Void, Never>?

    init(gitService: GitService, loadingIndicatorDelay: Duration = .milliseconds(500)) {
        self.gitService = gitService
        self.loadingIndicatorDelay = loadingIndicatorDelay
    }

    var activeDirectory: String? { activeTarget?.directory }
    var selectedFiles: [FileStatus] { files.filter { selectedFileKeys.contains(DiffViewerFileSelectionKey($0)) } }
    var isToolbarLoading: Bool { isStatsLoadingIndicatorVisible || isSelectedDiffLoadingIndicatorVisible }

    @discardableResult
    func switchToTarget(_ target: DiffWorkspaceTarget) -> Bool {
        guard target != activeTarget else {
            return false
        }

        targetGeneration &+= 1
        fileSelectionGeneration &+= 1
        cancelStatsLoad()
        cancelSelectedDiffLoad()

        activeTarget = target
        // Clear only visible state on target changes. Cached stats stay keyed by
        // project/worktree so returning to that target can hydrate immediately.
        files = []
        selectedFile = nil
        selectedFileKeys = []
        selectionAnchorKey = nil
        clearSelectedDiffPayload()
        setSelectedDiffLoadState(.idle)
        gitError = nil
        isGitRepository = true
        isLoadingFiles = true
        stats = statsCache[target.statsCacheKey] ?? .empty
        // A target switch starts a new visible context, so the delayed toolbar
        // spinner gets a fresh grace period instead of inheriting the old one.
        hideStatsLoadingIndicator()
        setStatsLoadState(.loading)
        return true
    }

    func clear() {
        targetGeneration &+= 1
        fileSelectionGeneration &+= 1
        cancelStatsLoad()
        cancelSelectedDiffLoad()
        activeTarget = nil
        files = []
        stats = .empty
        setStatsLoadState(.idle)
        selectedFile = nil
        selectedFileKeys = []
        selectionAnchorKey = nil
        clearSelectedDiffPayload()
        setSelectedDiffLoadState(.idle)
        isLoadingFiles = false
        gitError = nil
        isGitRepository = true
    }

    func clearGitError() { gitError = nil }
    func presentGitError(_ message: String) { gitError = message }
    func clearSelectedDiffPayload() {
        rawDiffContent = ""
        parsedDiff = nil
        imagePreview = nil
        selectedDiffErrorMessage = nil
    }

    func refreshStatusAndStartStats(for directory: String) async -> DiffWorkspaceRefreshSnapshot? {
        guard let target = activeTarget, target.directory == directory else {
            return nil
        }

        let generation = targetGeneration
        setStatsLoadState(.loading)

        do {
            let refreshedFiles = try await gitService.status(in: directory)
            guard isCurrent(target: target, generation: generation) else {
                return nil
            }

            let previousSelectedFiles = selectedFiles
            files = refreshedFiles
            reconcileSelectionAfterStatusRefresh(previousSelectedFiles: previousSelectedFiles)
            gitError = nil
            isGitRepository = true
            isLoadingFiles = false
            startStatsLoad(for: target, generation: generation, knownStatuses: refreshedFiles)
            return DiffWorkspaceRefreshSnapshot(
                target: target,
                generation: generation,
                files: refreshedFiles,
                error: nil,
                isGitRepository: true
            )
        } catch let error as GitError {
            let snapshot = applyStatusFailure(error, target: target, generation: generation)
            return snapshot
        } catch {
            let snapshot = applyStatusFailure(error, target: target, generation: generation)
            return snapshot
        }
    }

    func applyContextualRefreshErrorIfCurrent(_ snapshot: DiffWorkspaceRefreshSnapshot) {
        guard isCurrent(snapshot) else {
            return
        }

        if snapshot.error != nil || !snapshot.isGitRepository {
            cancelSelectedDiffLoad()
            selectedFile = nil
            selectedFileKeys = []
            selectionAnchorKey = nil
            clearSelectedDiffPayload()
            setSelectedDiffLoadState(.idle)
        }
    }

    func selectFile(
        _ file: FileStatus,
        in directory: String,
        behavior: DiffViewerFileSelectionBehavior = .single
    ) async {
        guard let preparedSelection = selectFileImmediately(file, in: directory, behavior: behavior) else {
            return
        }

        await loadSelectedFileDiff(preparedSelection)
    }

    func loadSelectedFileDiff(_ preparedSelection: DiffViewerPreparedFileSelection) async {
        guard isCurrent(target: preparedSelection.target, generation: preparedSelection.generation),
              activeTarget?.directory == preparedSelection.directory else {
            return
        }

        await loadDiff(
            for: preparedSelection.file,
            target: preparedSelection.target,
            in: preparedSelection.directory
        )
    }

    func selectFileImmediately(
        _ file: FileStatus,
        in directory: String,
        behavior: DiffViewerFileSelectionBehavior = .single
    ) -> DiffViewerPreparedFileSelection? {
        guard let target = activeTarget, target.directory == directory else {
            return nil
        }

        guard let previewFile = applySelection(file, behavior: behavior) else {
            clearSelectedDiffPreview()
            return nil
        }

        guard selectedFile != previewFile || parsedDiff == nil && rawDiffContent.isEmpty else {
            return nil
        }

        return DiffViewerPreparedFileSelection(
            file: previewFile,
            target: target,
            generation: targetGeneration,
            directory: directory
        )
    }

    func refreshSelectedDiffIfNeeded(snapshot: DiffWorkspaceRefreshSnapshot, reason: DiffViewerRefreshReason) async {
        guard isCurrent(snapshot) else {
            return
        }
        guard let selectedFile else {
            return
        }

        guard let updatedSelection = updatedSelection(matching: selectedFile) else {
            cancelSelectedDiffLoad()
            self.selectedFile = nil
            selectedFileKeys.remove(DiffViewerFileSelectionKey(selectedFile))
            if selectionAnchorKey == DiffViewerFileSelectionKey(selectedFile) {
                selectionAnchorKey = selectedFiles.first.map(DiffViewerFileSelectionKey.init)
            }
            if let fallbackSelection = selectedFiles.first {
                await loadDiff(for: fallbackSelection, target: snapshot.target, in: snapshot.target.directory)
                return
            }
            clearSelectedDiffPayload()
            setSelectedDiffLoadState(.idle)
            return
        }

        updateSelectionKey(from: selectedFile, to: updatedSelection)
        guard shouldReloadDiffPreview(from: selectedFile, to: updatedSelection, reason: reason) else {
            self.selectedFile = updatedSelection
            return
        }

        await loadDiff(for: updatedSelection, target: snapshot.target, in: snapshot.target.directory)
    }

    func isCurrent(_ snapshot: DiffWorkspaceRefreshSnapshot) -> Bool { isCurrent(target: snapshot.target, generation: snapshot.generation) }
    func waitForStatsForTesting() async {
        guard let statsLoad = inFlightStatsLoad else { return }

        _ = try? await statsLoad.task.value
        // Stats publish from a follow-up main-actor task after the service task resolves.
        for _ in 0..<100 where inFlightStatsLoad?.id == statsLoad.id { await Task.yield() }
    }

    func waitForLoadingIndicatorsForTesting() async {
        try? await Task.sleep(for: loadingIndicatorDelay + .milliseconds(10))
        await Task.yield()
    }
}

private extension DiffWorkspaceStore {
    struct DiffLoadContext {
        let target: DiffWorkspaceTarget
        let bindingGeneration: UInt64
        let selectionGeneration: UInt64
    }
    struct StatsLoad {
        let id: UUID
        let generation: UInt64
        let task: Task<DiffStats, Error>
    }

    private func applyStatusFailure(
        _ error: Error,
        target: DiffWorkspaceTarget,
        generation: UInt64
    ) -> DiffWorkspaceRefreshSnapshot? {
        guard isCurrent(target: target, generation: generation) else {
            return nil
        }

        cancelStatsLoad()
        files = []
        selectedFileKeys = []
        selectionAnchorKey = nil
        stats = .empty
        setStatsLoadState(.idle)
        // The active target's cached count is no longer trustworthy after a
        // failed status refresh, but caches for other project/worktree targets stay intact.
        statsCache.removeValue(forKey: target.statsCacheKey)
        isLoadingFiles = false

        if let gitError = error as? GitError, gitError == .notARepository {
            self.gitError = nil
            isGitRepository = false
            return DiffWorkspaceRefreshSnapshot(
                target: target,
                generation: generation,
                files: [],
                error: nil,
                isGitRepository: false
            )
        }

        let message = "Git status failed: \(error.localizedDescription)"
        self.gitError = message
        isGitRepository = true
        return DiffWorkspaceRefreshSnapshot(
            target: target,
            generation: generation,
            files: [],
            error: message,
            isGitRepository: true
        )
    }

    private func startStatsLoad(
        for target: DiffWorkspaceTarget,
        generation: UInt64,
        knownStatuses: [FileStatus]
    ) {
        cancelStatsLoad()
        setStatsLoadState(.loading)

        let gitService = gitService
        let task = Task.detached(priority: .utility) {
            try await gitService.diffStats(in: target.directory, knownStatuses: knownStatuses)
        }
        let statsLoadID = UUID()
        inFlightStatsLoad = StatsLoad(id: statsLoadID, generation: generation, task: task)

        Task { [weak self, task, target, generation, statsLoadID] in
            do {
                let refreshedStats = try await task.value
                self?.applyStats(refreshedStats, target: target, generation: generation, statsLoadID: statsLoadID)
            } catch is CancellationError {
                self?.finishStatsLoadIfCurrent(target: target, generation: generation, statsLoadID: statsLoadID, state: .idle)
            } catch {
                // Stats are auxiliary: file status can still be correct even if
                // numstat fails, so keep the pane usable and clear visible stats.
                self?.applyStatsFailure(target: target, generation: generation, statsLoadID: statsLoadID)
            }
        }
    }

    private func applyStats(
        _ refreshedStats: DiffStats,
        target: DiffWorkspaceTarget,
        generation: UInt64,
        statsLoadID: UUID
    ) {
        guard isCurrent(target: target, generation: generation),
              inFlightStatsLoad?.id == statsLoadID else {
            return
        }

        statsCache[target.statsCacheKey] = refreshedStats
        stats = refreshedStats
        setStatsLoadState(.loaded)
        inFlightStatsLoad = nil
    }

    private func applyStatsFailure(target: DiffWorkspaceTarget, generation: UInt64, statsLoadID: UUID) {
        guard isCurrent(target: target, generation: generation),
              inFlightStatsLoad?.id == statsLoadID else {
            return
        }

        stats = .empty
        setStatsLoadState(.failed)
        // Only evict the failed target; target switches clear visible state
        // without deleting other cached project/worktree stats.
        statsCache.removeValue(forKey: target.statsCacheKey)
        inFlightStatsLoad = nil
    }

    private func finishStatsLoadIfCurrent(
        target: DiffWorkspaceTarget,
        generation: UInt64,
        statsLoadID: UUID,
        state: DiffWorkspaceLoadState
    ) {
        guard isCurrent(target: target, generation: generation),
              inFlightStatsLoad?.id == statsLoadID else {
            return
        }

        setStatsLoadState(state)
        inFlightStatsLoad = nil
    }

    private func beginDiffLoad(for file: FileStatus, target: DiffWorkspaceTarget) -> DiffLoadContext {
        selectedFile = file
        let bindingGeneration = targetGeneration
        fileSelectionGeneration &+= 1
        cancelSelectedDiffLoad()
        clearSelectedDiffPayload()
        gitError = nil
        setSelectedDiffLoadState(.loading)
        return DiffLoadContext(
            target: target,
            bindingGeneration: bindingGeneration,
            selectionGeneration: fileSelectionGeneration
        )
    }

    private func loadDiff(for file: FileStatus, target: DiffWorkspaceTarget, in directory: String) async {
        let context = beginDiffLoad(for: file, target: target)
        let task = DiffViewerDiffTaskFactory.makeTask(for: file, in: directory, gitService: gitService)
        let diffLoadID = UUID()
        inFlightDiffLoad = (id: diffLoadID, task: task)

        do {
            let result = try await task.value
            applyDiffLoadResult(result, for: file, in: directory, context: context, diffLoadID: diffLoadID)
        } catch is CancellationError {
            // A newer target or file selection superseded this load.
        } catch {
            applyDiffLoadError(error, for: file, in: directory, context: context, diffLoadID: diffLoadID)
        }

        finishDiffLoad(diffLoadID)
    }

    private func clearSelectedDiffPreview() {
        fileSelectionGeneration &+= 1
        cancelSelectedDiffLoad()
        selectedFile = nil
        clearSelectedDiffPayload()
        setSelectedDiffLoadState(.idle)
    }

    private func applyDiffLoadResult(
        _ result: DiffLoadResult,
        for file: FileStatus,
        in directory: String,
        context: DiffLoadContext,
        diffLoadID: UUID
    ) {
        guard matchesCurrentDiffLoad(file: file, directory: directory, context: context, diffLoadID: diffLoadID) else {
            return
        }

        rawDiffContent = result.raw
        parsedDiff = result.parsed
        imagePreview = result.imagePreview
        selectedDiffErrorMessage = nil
        gitError = nil
        setSelectedDiffLoadState(.loaded)
    }

    private func applyDiffLoadError(
        _ error: Error,
        for file: FileStatus,
        in directory: String,
        context: DiffLoadContext,
        diffLoadID: UUID
    ) {
        guard matchesCurrentDiffLoad(file: file, directory: directory, context: context, diffLoadID: diffLoadID) else {
            return
        }

        clearSelectedDiffPayload()
        selectedDiffErrorMessage = error.localizedDescription
        setSelectedDiffLoadState(.failed)
    }

    private func matchesCurrentDiffLoad(
        file: FileStatus,
        directory: String,
        context: DiffLoadContext,
        diffLoadID: UUID
    ) -> Bool {
        isCurrent(target: context.target, generation: context.bindingGeneration)
            && context.target.directory == directory
            && fileSelectionGeneration == context.selectionGeneration
            && selectedFile?.path == file.path
            && selectedFile?.isStaged == file.isStaged
            && inFlightDiffLoad?.id == diffLoadID
    }

    private func finishDiffLoad(_ diffLoadID: UUID) {
        if inFlightDiffLoad?.id == diffLoadID {
            inFlightDiffLoad = nil
            if selectedDiffLoadState == .loading {
                setSelectedDiffLoadState(.loaded)
            }
        }
    }

    private func cancelStatsLoad() {
        inFlightStatsLoad?.task.cancel()
        inFlightStatsLoad = nil
    }

    private func cancelSelectedDiffLoad() {
        inFlightDiffLoad?.task.cancel()
        inFlightDiffLoad = nil
        hideSelectedDiffLoadingIndicator()
    }
    private func isCurrent(target: DiffWorkspaceTarget, generation: UInt64) -> Bool { activeTarget == target && targetGeneration == generation }
}
