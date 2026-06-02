import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class DiffViewerViewModel {
    typealias ContextualAction = DiffViewerContextualAction
    typealias RefreshReason = DiffViewerRefreshReason

    private typealias RefreshRequest = DiffViewerRefreshRequest

    var files: [FileStatus] { diffStore.files }
    var diffStats: DiffStats { diffStore.stats }
    var diffStatsLoadState: DiffWorkspaceLoadState { diffStore.statsLoadState }
    var selectedFile: FileStatus? { diffStore.selectedFile }
    var selectedFiles: [FileStatus] { diffStore.selectedFiles }
    var parsedDiff: DiffFile? { diffStore.parsedDiff }
    var imagePreview: DiffImagePreview? { diffStore.imagePreview }
    var rawDiffContent: String { diffStore.rawDiffContent }
    var selectedDiffErrorMessage: String? { diffStore.selectedDiffErrorMessage }
    var isLoadingFiles: Bool { diffStore.isLoadingFiles }
    var isSelectedDiffPending: Bool { diffStore.selectedDiffLoadState == .loading }
    var isLoadingSelectedDiff: Bool { diffStore.isSelectedDiffLoadingIndicatorVisible }
    var isDiffToolbarLoading: Bool { diffStore.isToolbarLoading }
    private(set) var contextualAction: ContextualAction = .none
    var gitError: String? { diffStore.gitError }
    var activeDirectory: String? { diffStore.activeDirectory }
    var isGitRepository: Bool { diffStore.isGitRepository }
    var aheadCommits: [CommitInfo] = []
    var selectedCommit: CommitInfo?
    var selectedCommitIDs: Set<String> = []
    var selectedCommits: [CommitInfo] { aheadCommits.filter { selectedCommitIDs.contains($0.id) } }
    var commitDiffFiles: [DiffFile] = []
    var commitImagePreviews: [String: DiffImagePreview] = [:]
    var rawCommitDiffContent = ""
    var commitsLoadState: DiffWorkspaceLoadState = .idle
    var selectedCommitDiffLoadState: DiffWorkspaceLoadState = .idle
    var selectedCommitDiffErrorMessage: String?
    private(set) var workspaceRefreshRevision: UInt64 = 0
    var isCommitModeActive = false
    var commitListTarget: DiffWorkspaceTarget?
    var isCommitListRefreshNeeded = false
    var pendingCommitReloadTarget: DiffWorkspaceTarget?
    var collapsedCommitFileIDsByCommitHash: [String: Set<String>] = [:]
    var commitSelectionAnchorID: String?

    var isLoadingCommits: Bool { commitsLoadState == .loading }
    var isLoadingSelectedCommitDiff: Bool { selectedCommitDiffLoadState == .loading }
    var selectedCommitCollapsedFileIDs: Set<String> {
        guard let selectedCommit else {
            return []
        }

        return collapsedCommitFileIDsByCommitHash[selectedCommit.hash] ?? []
    }

    private var activeConversationIds: Set<String> = []
    let gitService: GitService
    let diffStore: DiffWorkspaceStore
    private let fileListManager: FileListManager
    private let agentsManager: any AgentsManager
    private let contextualActionResolver: DiffViewerContextualActionResolver
    private let fsEventDebounceDuration: Duration
    private let idlePollInterval: Duration
    @ObservationIgnored
    private lazy var refreshScheduler: DiffViewerRefreshScheduler<RefreshRequest> = .init(
        merge: { $0.merged(with: $1) },
        perform: { [weak self] request in
            guard let self else {
                return
            }
            await self.performRefresh(request)
        }
    )
    @ObservationIgnored
    private lazy var watchController: DiffViewerWatchController = .init(
        fsEventDebounceDuration: fsEventDebounceDuration,
        idlePollInterval: idlePollInterval,
        onIdlePoll: { [weak self] directory in
            guard let self else {
                return
            }
            await self.refresh(in: directory, reason: .idlePoll)
        },
        onFSRefresh: { [weak self] directory, changedPaths in
            guard let self else {
                return
            }
            await self.refresh(in: directory, reason: .fsEvent(changedPaths: changedPaths))
        }
    )
    private var watchingEnabled = false
    var commitGeneration: UInt64 = 0
    var inFlightCommitListLoad: (id: UUID, task: Task<[CommitInfo], Error>)?
    var inFlightCommitDiffLoad: (id: UUID, task: Task<DiffViewerCommitDiffLoadResult, Error>)?
    private var agentStatusObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?
    private var appWillTerminateObserver: NSObjectProtocol?
    let imagePreviewLoader: DiffImagePreviewLoader
    let imagePreviewOpener: @MainActor (URL) -> Void

    init(
        gitService: GitService,
        gitHubService: GitHubService,
        diffStore: DiffWorkspaceStore? = nil,
        fileListManager: FileListManager,
        agentsManager: any AgentsManager,
        imagePreviewLoader: DiffImagePreviewLoader = .shared,
        imagePreviewOpener: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        fsEventDebounceDuration: Duration = .milliseconds(500),
        idlePollInterval: Duration = .seconds(60)
    ) {
        self.gitService = gitService
        self.diffStore = diffStore ?? DiffWorkspaceStore(gitService: gitService)
        self.fileListManager = fileListManager
        self.agentsManager = agentsManager
        self.imagePreviewLoader = imagePreviewLoader
        self.imagePreviewOpener = imagePreviewOpener
        self.contextualActionResolver = DiffViewerContextualActionResolver(gitService: gitService, gitHubService: gitHubService)
        self.fsEventDebounceDuration = fsEventDebounceDuration
        self.idlePollInterval = idlePollInterval

        agentStatusObserver = makeAgentStatusObserver()

        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let directory = self.activeDirectory else {
                    return
                }

                await self.refresh(in: directory, reason: .appBecameActive)
            }
        }

        appWillTerminateObserver = NotificationCenter.default.addObserver(
            forName: .appWillTerminate,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tearDown()
            }
        }
    }

    deinit { MainActor.assumeIsolated { tearDown() } }

    private func makeAgentStatusObserver() -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .agentStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // `.agentStatusChanged` is shared between runtime transitions (posted with a `signal`
            // userInfo key) and unread-flag flips from `DefaultNotificationManager` (no `signal`).
            // Only the former may have touched the filesystem, so skip the rescan otherwise.
            guard notification.userInfo?["signal"] is ActivitySignal else {
                return
            }
            let conversationId = notification.userInfo?["conversationId"] as? String
            Task { @MainActor in
                guard let self, let directory = self.activeDirectory else {
                    return
                }

                if let conversationId {
                    guard self.activeConversationIds.contains(conversationId) else {
                        return
                    }
                    if self.agentsManager.status(for: conversationId) == .busy {
                        return
                    }
                }

                await self.refreshAndInvalidateFileList(in: directory, reason: .agentTurnCompleted)
            }
        }
    }

    func switchToDirectory(
        _ directory: String,
        baseRef: String = "main",
        remoteName: String?,
        conversationIds: Set<String>
    ) async {
        await switchToTarget(
            DiffViewerSwitchTarget(
                projectPath: directory,
                worktreePath: nil,
                directory: directory,
                baseRef: baseRef,
                remoteName: remoteName,
                conversationIds: conversationIds
            )
        )
    }

    func switchToTarget(_ target: DiffViewerSwitchTarget) async {
        activeConversationIds = target.conversationIds
        guard target.workspaceTarget != diffStore.activeTarget else {
            return
        }

        watchController.stopWatching()
        if diffStore.switchToTarget(target.workspaceTarget) {
            workspaceRefreshRevision &+= 1
        }
        contextualAction = .none
        clearCommitState()

        contextualActionResolver.invalidatePRCache()
        refreshScheduler.clearPending()

        if watchingEnabled { watchController.startWatching(target.directory) }

        await refresh(in: target.directory, reason: .threadSwitch)
    }

    func setWatchingEnabled(_ enabled: Bool) {
        guard watchingEnabled != enabled else {
            return
        }

        watchingEnabled = enabled
        guard let activeDirectory else {
            return
        }

        if enabled {
            watchController.startWatching(activeDirectory)
        } else {
            watchController.stopWatching()
        }
    }

    func clear() {
        watchController.stopWatching()
        activeConversationIds = []
        diffStore.clear()
        workspaceRefreshRevision &+= 1
        contextualAction = .none
        clearCommitState()
        refreshScheduler.clearPending()
        contextualActionResolver.invalidatePRCache()
    }

    func clearGitError() { diffStore.clearGitError() }

    func presentGitError(_ message: String) { diffStore.presentGitError(message) }

    func refresh(in directory: String, reason: RefreshReason) async {
        await refreshScheduler.enqueue(
            RefreshRequest(
                directory: directory,
                reason: reason,
                invalidateFileListCache: false,
                invalidatePRCache: false
            )
        )
    }

    func refreshAndInvalidateFileList(in directory: String, reason: RefreshReason) async {
        await refreshScheduler.enqueue(
            RefreshRequest(
                directory: directory,
                reason: reason,
                invalidateFileListCache: true,
                invalidatePRCache: reason != .localGitMutation
            )
        )
    }

    func selectFile(
        _ file: FileStatus,
        in directory: String,
        behavior: DiffViewerFileSelectionBehavior = .single
    ) async {
        await diffStore.selectFile(file, in: directory, behavior: behavior)
    }

    func selectFileImmediately(
        _ file: FileStatus,
        in directory: String,
        behavior: DiffViewerFileSelectionBehavior = .single
    ) -> DiffViewerPreparedFileSelection? {
        diffStore.selectFileImmediately(file, in: directory, behavior: behavior)
    }

    func loadSelectedFileDiff(_ preparedSelection: DiffViewerPreparedFileSelection) async {
        await diffStore.loadSelectedFileDiff(preparedSelection)
    }

    func loadAheadCommitsForActiveTarget() async {
        guard let target = diffStore.activeTarget else {
            clearCommitState()
            return
        }

        isCommitModeActive = true
        let needsRefresh = isCommitListRefreshNeeded && commitListTarget == target
        let shouldPreserveVisibleCommitState = commitListTarget == target &&
            (!aheadCommits.isEmpty || selectedCommit != nil || !commitDiffFiles.isEmpty || !rawCommitDiffContent.isEmpty)
        await loadAheadCommits(
            for: target,
            preservesSelectedDiff: needsRefresh || shouldPreserveVisibleCommitState,
            forceReload: needsRefresh
        )
    }

    func setCommitModeActive(_ isActive: Bool) {
        isCommitModeActive = isActive
        if !isActive {
            // Leaving commit mode discards queued reload work, but the cached list still needs
            // a preserving refresh when the user comes back to the same target.
            if let pendingCommitReloadTarget,
               pendingCommitReloadTarget == commitListTarget {
                isCommitListRefreshNeeded = true
            }
            pendingCommitReloadTarget = nil
        }
    }

    func toggleSelectedCommitFileCollapse(fileID: String) {
        guard let selectedCommit else {
            return
        }

        var collapsedFileIDs = collapsedCommitFileIDsByCommitHash[selectedCommit.hash] ?? []
        if collapsedFileIDs.contains(fileID) {
            collapsedFileIDs.remove(fileID)
        } else {
            collapsedFileIDs.insert(fileID)
        }
        if collapsedFileIDs.isEmpty {
            collapsedCommitFileIDsByCommitHash.removeValue(forKey: selectedCommit.hash)
        } else {
            collapsedCommitFileIDsByCommitHash[selectedCommit.hash] = collapsedFileIDs
        }
    }

    func isFileSelected(_ file: FileStatus) -> Bool {
        diffStore.selectedFileKeys.contains(DiffViewerFileSelectionKey(file))
    }

    func stage(files: [FileStatus], in directory: String) async throws {
        try await stage(paths: DiffViewerPathSupport.uniquePaths(files.map(\.path)), in: directory)
    }

    func stage(paths: [String], in directory: String) async throws {
        try await gitService.stage(paths: paths, in: directory)
        await refreshAndInvalidateFileList(in: directory, reason: .localGitMutation)
    }

    func unstage(files: [FileStatus], in directory: String) async throws {
        try await unstage(paths: DiffViewerPathSupport.uniquePaths(files.map(\.path)), in: directory)
    }

    func unstage(paths: [String], in directory: String) async throws {
        try await gitService.unstage(paths: paths, in: directory)
        await refreshAndInvalidateFileList(in: directory, reason: .localGitMutation)
    }

    func discard(files: [FileStatus], in directory: String) async throws {
        let stagedFiles = files.filter(\.isStaged)
        let stagedPaths = DiffViewerPathSupport.discardPaths(for: stagedFiles)
        let stagedPathSet = Set(stagedPaths)

        let unstagedPaths = DiffViewerPathSupport.discardPaths(for: files.filter { !$0.isStaged })
            .filter { !stagedPathSet.contains($0) }

        if !stagedPaths.isEmpty {
            try await gitService.discard(paths: stagedPaths, scope: .all, in: directory)
        }

        if !unstagedPaths.isEmpty {
            try await gitService.discard(paths: unstagedPaths, scope: .worktreeOnly, in: directory)
        }

        await refreshAndInvalidateFileList(in: directory, reason: .localGitMutation)
    }

    func discard(paths: [String], in directory: String) async throws {
        try await gitService.discard(paths: paths, scope: .all, in: directory)
        await refreshAndInvalidateFileList(in: directory, reason: .localGitMutation)
    }

    func tearDown() {
        if let agentStatusObserver {
            NotificationCenter.default.removeObserver(agentStatusObserver)
            self.agentStatusObserver = nil
        }

        if let appActiveObserver {
            NotificationCenter.default.removeObserver(appActiveObserver)
            self.appActiveObserver = nil
        }

        if let appWillTerminateObserver {
            NotificationCenter.default.removeObserver(appWillTerminateObserver)
            self.appWillTerminateObserver = nil
        }

        watchController.stopWatching()
        cancelCommitLoads()
    }

    func handleFSEventsForTesting(changedPaths: Set<String>) {
        guard let activeDirectory else { return }
        watchController.handleFSEventsForTesting(changedPaths: changedPaths, directory: activeDirectory)
    }
}

private extension DiffViewerViewModel {
    private func performRefresh(_ request: RefreshRequest) async {
        if request.invalidatePRCache {
            contextualActionResolver.invalidatePRCache()
        }
        if request.invalidateFileListCache {
            await fileListManager.invalidateCache(for: request.directory)
        }

        guard let snapshot = await diffStore.refreshStatusAndStartStats(for: request.directory) else {
            return
        }
        if shouldMarkCommitListStaleAfterInactiveRefresh(snapshot: snapshot, reason: request.reason) {
            isCommitListRefreshNeeded = true
        }

        if snapshot.error != nil {
            contextualAction = .none
            diffStore.applyContextualRefreshErrorIfCurrent(snapshot)
            return
        }

        if !snapshot.isGitRepository {
            contextualAction = .none
            diffStore.applyContextualRefreshErrorIfCurrent(snapshot)
            return
        }

        let action = await contextualActionResolver.determineAction(
            files: snapshot.files,
            baseRef: snapshot.target.baseRef,
            remoteName: snapshot.target.remoteName,
            directory: snapshot.target.directory
        )
        guard diffStore.isCurrent(snapshot) else {
            return
        }

        contextualAction = action
        await diffStore.refreshSelectedDiffIfNeeded(snapshot: snapshot, reason: request.reason)
        workspaceRefreshRevision &+= 1
        if shouldReloadCommitsAfterWorkspaceRefresh(snapshot: snapshot, reason: request.reason) {
            await loadAheadCommits(for: snapshot.target, preservesSelectedDiff: true, forceReload: true)
        }
    }

}

private extension DiffViewerViewModel {
    func shouldReloadCommitsAfterWorkspaceRefresh(snapshot: DiffWorkspaceRefreshSnapshot, reason: RefreshReason) -> Bool {
        // Thread switches already trigger an initial commit load from the view; reloading after
        // that first status refresh causes the commits pane to clear and repopulate.
        guard reason != .threadSwitch,
              isCommitModeActive,
              commitListTarget == snapshot.target,
              diffStore.isCurrent(snapshot),
              commitsLoadState == .loaded || commitsLoadState == .failed || selectedCommit != nil || !aheadCommits.isEmpty else {
            return false
        }

        return true
    }

    func shouldMarkCommitListStaleAfterInactiveRefresh(snapshot: DiffWorkspaceRefreshSnapshot, reason: RefreshReason) -> Bool {
        // Inactive refreshes skip the Git log work; remember that cached commits
        // need a preserving reload the next time commit mode becomes visible.
        guard reason != .threadSwitch,
              !isCommitModeActive,
              commitListTarget == snapshot.target,
              diffStore.isCurrent(snapshot) else {
            return false
        }

        return true
    }
}
