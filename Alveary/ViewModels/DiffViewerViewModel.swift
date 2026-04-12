import AppKit
import Foundation
import Observation

// swiftlint:disable file_length

@MainActor
@Observable
final class DiffViewerViewModel {
    typealias ContextualAction = DiffViewerContextualAction
    typealias RefreshReason = DiffViewerRefreshReason

    private typealias DiffLoadResult = DiffViewerDiffLoadResult
    private typealias RefreshRequest = DiffViewerRefreshRequest

    private(set) var files: [FileStatus] = []
    private(set) var selectedFile: FileStatus?
    private(set) var parsedDiff: DiffFile?
    private(set) var rawDiffContent = ""
    private(set) var isLoadingSelectedDiff = false
    private(set) var contextualAction: ContextualAction = .none
    private(set) var gitError: String?
    private(set) var activeDirectory: String?
    private(set) var isGitRepository = true

    private var activeConversationIds: Set<String> = []
    private var baseRef = "main"
    private var remoteName: String?
    private let gitService: GitService
    private let gitHubService: GitHubService
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
    private var inFlightDiffLoad: (id: UUID, task: Task<DiffLoadResult, Error>)?
    private var directoryGeneration: UInt64 = 0
    private var fileSelectionGeneration: UInt64 = 0
    private var watchingEnabled = false
    private var agentStatusObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?
    private var appWillTerminateObserver: NSObjectProtocol?

    init(
        gitService: GitService,
        gitHubService: GitHubService,
        fileListManager: FileListManager,
        agentsManager: any AgentsManager,
        fsEventDebounceDuration: Duration = .milliseconds(500),
        idlePollInterval: Duration = .seconds(60)
    ) {
        self.gitService = gitService
        self.gitHubService = gitHubService
        self.fileListManager = fileListManager
        self.agentsManager = agentsManager
        self.contextualActionResolver = DiffViewerContextualActionResolver(gitService: gitService, gitHubService: gitHubService)
        self.fsEventDebounceDuration = fsEventDebounceDuration
        self.idlePollInterval = idlePollInterval

        agentStatusObserver = NotificationCenter.default.addObserver(
            forName: .agentStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
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

    func switchToDirectory(
        _ directory: String,
        baseRef: String = "main",
        remoteName: String?,
        conversationIds: Set<String>
    ) async {
        activeConversationIds = conversationIds
        guard directory != activeDirectory || baseRef != self.baseRef || remoteName != self.remoteName else {
            return
        }

        let directoryChanged = directory != activeDirectory
        directoryGeneration &+= 1
        fileSelectionGeneration &+= 1
        inFlightDiffLoad?.task.cancel()
        inFlightDiffLoad = nil
        self.baseRef = baseRef
        self.remoteName = remoteName
        watchController.stopWatching()
        activeDirectory = directory

        if directoryChanged {
            files = []
            selectedFile = nil
            parsedDiff = nil
            rawDiffContent = ""
            isLoadingSelectedDiff = false
            contextualAction = .none
            gitError = nil
            isGitRepository = true
        }

        contextualActionResolver.invalidatePRCache()
        refreshScheduler.clearPending()

        if watchingEnabled { watchController.startWatching(directory) }

        await refresh(in: directory, reason: .threadSwitch)
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
        directoryGeneration &+= 1
        fileSelectionGeneration &+= 1
        inFlightDiffLoad?.task.cancel()
        inFlightDiffLoad = nil
        watchController.stopWatching()
        activeDirectory = nil
        activeConversationIds = []
        baseRef = "main"
        remoteName = nil
        files = []
        selectedFile = nil
        parsedDiff = nil
        rawDiffContent = ""
        isLoadingSelectedDiff = false
        contextualAction = .none
        gitError = nil
        isGitRepository = true
        refreshScheduler.clearPending()
        contextualActionResolver.invalidatePRCache()
    }

    func clearGitError() { gitError = nil }

    func presentGitError(_ message: String) { gitError = message }

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

    func selectFile(_ file: FileStatus, in directory: String) async {
        let context = beginDiffLoad(for: file)
        let task = DiffViewerDiffTaskFactory.makeTask(for: file, in: directory, gitService: gitService)
        let diffLoadID = UUID()
        inFlightDiffLoad = (id: diffLoadID, task: task)

        do {
            let result = try await task.value
            applyDiffLoadResult(result, for: file, in: directory, context: context, diffLoadID: diffLoadID)
        } catch is CancellationError {
            // A newer selection superseded this load.
        } catch {
            applyDiffLoadError(error, for: file, in: directory, context: context, diffLoadID: diffLoadID)
        }

        finishDiffLoad(diffLoadID)
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
    }

    func handleFSEventsForTesting(changedPaths: Set<String>) {
        guard let activeDirectory else { return }
        watchController.handleFSEventsForTesting(changedPaths: changedPaths, directory: activeDirectory)
    }
}

private extension DiffViewerViewModel {
    struct DiffLoadContext {
        let bindingGeneration: UInt64
        let selectionGeneration: UInt64
    }

    // Keeping refresh state handling colocated with the view-model state avoids
    // widening access across companion files just to satisfy lint structure.
    // swiftlint:disable:next function_body_length
    private func performRefresh(_ request: RefreshRequest) async {
        if request.invalidatePRCache {
            contextualActionResolver.invalidatePRCache()
        }
        if request.invalidateFileListCache {
            await fileListManager.invalidateCache(for: request.directory)
        }

        let generation = directoryGeneration
        let refreshedFiles: [FileStatus]
        let refreshedError: String?
        let refreshedIsGitRepository: Bool

        do {
            refreshedFiles = try await gitService.status(in: request.directory)
            refreshedError = nil
            refreshedIsGitRepository = true
        } catch let error as GitError {
            if error == .notARepository {
                refreshedFiles = []
                refreshedError = nil
                refreshedIsGitRepository = false
            } else {
                refreshedFiles = []
                refreshedError = "Git status failed: \(error.localizedDescription)"
                refreshedIsGitRepository = true
            }
        } catch {
            refreshedFiles = []
            refreshedError = "Git status failed: \(error.localizedDescription)"
            refreshedIsGitRepository = true
        }

        guard isCurrentBinding(directory: request.directory, generation: generation) else {
            return
        }

        files = refreshedFiles
        gitError = refreshedError
        isGitRepository = refreshedIsGitRepository

        if refreshedError != nil {
            contextualAction = .none
            return
        }

        if !refreshedIsGitRepository {
            contextualAction = .none
            await refreshSelectedDiffIfNeeded(in: request.directory, generation: generation, reason: request.reason)
            return
        }

        let action = await contextualActionResolver.determineAction(
            files: refreshedFiles,
            baseRef: baseRef,
            remoteName: remoteName,
            directory: request.directory
        )
        guard isCurrentBinding(directory: request.directory, generation: generation) else {
            return
        }

        contextualAction = action
        await refreshSelectedDiffIfNeeded(in: request.directory, generation: generation, reason: request.reason)
    }

    private func beginDiffLoad(for file: FileStatus) -> DiffLoadContext {
        selectedFile = file
        let bindingGeneration = directoryGeneration
        fileSelectionGeneration &+= 1
        inFlightDiffLoad?.task.cancel()
        inFlightDiffLoad = nil
        rawDiffContent = ""
        parsedDiff = nil
        gitError = nil
        isLoadingSelectedDiff = true
        return DiffLoadContext(
            bindingGeneration: bindingGeneration,
            selectionGeneration: fileSelectionGeneration
        )
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
        gitError = nil
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

        rawDiffContent = ""
        parsedDiff = nil
        gitError = "Diff failed: \(error.localizedDescription)"
    }

    private func matchesCurrentDiffLoad(
        file: FileStatus,
        directory: String,
        context: DiffLoadContext,
        diffLoadID: UUID
    ) -> Bool {
        isCurrentBinding(directory: directory, generation: context.bindingGeneration)
            && fileSelectionGeneration == context.selectionGeneration
            && selectedFile?.path == file.path
            && selectedFile?.isStaged == file.isStaged
            && inFlightDiffLoad?.id == diffLoadID
    }

    private func finishDiffLoad(_ diffLoadID: UUID) {
        if inFlightDiffLoad?.id == diffLoadID {
            inFlightDiffLoad = nil
            isLoadingSelectedDiff = false
        }
    }

    private func refreshSelectedDiffIfNeeded(in directory: String, generation: UInt64, reason: RefreshReason) async {
        guard isCurrentBinding(directory: directory, generation: generation) else {
            return
        }
        guard let selectedFile else {
            return
        }

        let selectedAnchor = selectedFile.originalPath ?? selectedFile.path
        let updatedSelection = files.first {
            $0.path == selectedFile.path && $0.isStaged == selectedFile.isStaged
        } ?? files.first {
            $0.path == selectedFile.path
        } ?? files.first {
            ($0.originalPath ?? $0.path) == selectedAnchor && $0.isStaged == selectedFile.isStaged
        } ?? files.first {
            ($0.originalPath ?? $0.path) == selectedAnchor
        }

        guard let updatedSelection else {
            inFlightDiffLoad?.task.cancel()
            inFlightDiffLoad = nil
            self.selectedFile = nil
            parsedDiff = nil
            rawDiffContent = ""
            isLoadingSelectedDiff = false
            return
        }

        let selectionChanged = updatedSelection.path != selectedFile.path
            || updatedSelection.originalPath != selectedFile.originalPath
            || updatedSelection.isStaged != selectedFile.isStaged
            || updatedSelection.status != selectedFile.status

        let shouldReloadDiff: Bool
        switch reason {
        case .manual, .appBecameActive, .localGitMutation:
            shouldReloadDiff = true
        case .threadSwitch, .agentTurnCompleted, .idlePoll:
            shouldReloadDiff = selectionChanged
        case .fsEvent(let changedPaths):
            let selectedPaths = Set([updatedSelection.path, updatedSelection.originalPath].compactMap { $0 })
            shouldReloadDiff = selectionChanged || !changedPaths.isDisjoint(with: selectedPaths)
        }

        guard shouldReloadDiff else {
            self.selectedFile = updatedSelection
            return
        }

        await selectFile(updatedSelection, in: directory)
    }

    private func isCurrentBinding(directory: String, generation: UInt64) -> Bool {
        activeDirectory == directory && directoryGeneration == generation
    }
}

// swiftlint:enable file_length
