import AppKit
import CoreServices
import Foundation
import Observation

private let diffViewerFSEventCallback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
    DiffViewerViewModel.handleWatchEventCallback(
        info: info,
        count: numEvents,
        eventPaths: eventPaths
    )
}

private final class DiffViewerWatchContext {
    weak var owner: DiffViewerViewModel?
    let rootDirectory: String

    init(owner: DiffViewerViewModel, rootDirectory: String) {
        self.owner = owner
        self.rootDirectory = rootDirectory
    }
}

@MainActor
@Observable
final class DiffViewerViewModel {
    private struct RefreshRequest {
        let directory: String
        let reason: RefreshReason
        let invalidateFileListCache: Bool
        let invalidatePRCache: Bool

        func merged(with newer: RefreshRequest) -> RefreshRequest {
            guard directory == newer.directory else {
                return newer
            }

            return RefreshRequest(
                directory: directory,
                reason: reason.merged(with: newer.reason),
                invalidateFileListCache: invalidateFileListCache || newer.invalidateFileListCache,
                invalidatePRCache: invalidatePRCache || newer.invalidatePRCache
            )
        }
    }

    private(set) var files: [FileStatus] = []
    private(set) var selectedFile: FileStatus?
    private(set) var parsedDiff: DiffFile?
    private(set) var rawDiffContent = ""
    private(set) var contextualAction: ContextualAction = .none
    private(set) var gitError: String?
    private(set) var activeDirectory: String?

    private var activeConversationIds: Set<String> = []
    private var baseRef = "main"
    private var remoteName: String?
    private let gitService: GitService
    private let gitHubService: GitHubService
    private let fileListManager: FileListManager
    private let agentsManager: any AgentsManager
    private let fsEventDebounceDuration: Duration
    private let idlePollInterval: Duration
    private var cachedPRs: [PRInfo]?
    private var prCacheTime: Date = .distantPast
    private static let prCacheTTL: TimeInterval = 60
    private var inFlightRefresh: (id: UUID, task: Task<Void, Never>)?
    private var pendingRefresh: RefreshRequest?
    private var directoryGeneration: UInt64 = 0
    private var fileSelectionGeneration: UInt64 = 0
    private var fsEventStream: FSEventStreamRef?
    private var fsEventQueue: DispatchQueue?
    private var watchContextRetain: Unmanaged<DiffViewerWatchContext>?
    private var debounceTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var watchingEnabled = false
    private var pendingChangedPaths: Set<String> = []
    private var agentStatusObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?
    private var appWillTerminateObserver: NSObjectProtocol?

    enum ContextualAction: Equatable {
        case none
        case commit
        case openPR
        case viewPR(url: String)
    }

    enum RefreshReason: Equatable {
        case fsEvent(changedPaths: Set<String>)
        case agentTurnCompleted
        case appBecameActive
        case localGitMutation
        case manual
        case idlePoll
        case threadSwitch

        fileprivate func merged(with newer: RefreshReason) -> RefreshReason {
            switch (self, newer) {
            case let (.fsEvent(existingPaths), .fsEvent(newPaths)):
                return .fsEvent(changedPaths: existingPaths.union(newPaths))
            default:
                return priority >= newer.priority ? self : newer
            }
        }

        private var priority: Int {
            switch self {
            case .manual:
                return 6
            case .localGitMutation:
                return 5
            case .appBecameActive:
                return 4
            case .threadSwitch:
                return 3
            case .agentTurnCompleted:
                return 2
            case .fsEvent:
                return 1
            case .idlePoll:
                return 0
            }
        }
    }

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

    deinit {
        MainActor.assumeIsolated {
            tearDown()
        }
    }

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
        self.baseRef = baseRef
        self.remoteName = remoteName
        stopWatching()
        activeDirectory = directory

        if directoryChanged {
            files = []
            selectedFile = nil
            parsedDiff = nil
            rawDiffContent = ""
            contextualAction = .none
            gitError = nil
        }

        invalidatePRCache()
        pendingRefresh = nil

        if watchingEnabled {
            startWatching(directory)
        }

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
            startWatching(activeDirectory)
        } else {
            stopWatching()
        }
    }

    func clear() {
        directoryGeneration &+= 1
        fileSelectionGeneration &+= 1
        stopWatching()
        activeDirectory = nil
        activeConversationIds = []
        baseRef = "main"
        remoteName = nil
        files = []
        selectedFile = nil
        parsedDiff = nil
        rawDiffContent = ""
        contextualAction = .none
        gitError = nil
        pendingChangedPaths = []
        pendingRefresh = nil
        invalidatePRCache()
    }

    func clearGitError() {
        gitError = nil
    }

    func refresh(in directory: String, reason: RefreshReason) async {
        await enqueueRefresh(
            RefreshRequest(
                directory: directory,
                reason: reason,
                invalidateFileListCache: false,
                invalidatePRCache: false
            )
        )
    }

    func refreshAndInvalidateFileList(in directory: String, reason: RefreshReason) async {
        await enqueueRefresh(
            RefreshRequest(
                directory: directory,
                reason: reason,
                invalidateFileListCache: true,
                invalidatePRCache: reason != .localGitMutation
            )
        )
    }

    func selectFile(_ file: FileStatus, in directory: String) async {
        selectedFile = file
        let bindingGeneration = directoryGeneration
        fileSelectionGeneration &+= 1
        let selectionGeneration = fileSelectionGeneration

        do {
            let raw: String
            if file.status == .untracked {
                raw = try await gitService.syntheticAddedDiff(for: file.path, in: directory)
            } else {
                raw = try await gitService.diff(
                    paths: diffPaths(for: file),
                    scope: file.isStaged ? .staged : .unstaged,
                    in: directory
                )
            }

            guard isCurrentBinding(directory: directory, generation: bindingGeneration),
                  fileSelectionGeneration == selectionGeneration,
                  selectedFile?.path == file.path,
                  selectedFile?.isStaged == file.isStaged else {
                return
            }

            guard raw.utf8.count <= 5 * 1024 * 1024 else {
                rawDiffContent = ""
                parsedDiff = nil
                gitError = "Diff preview exceeded 5MB"
                return
            }

            let parsed = await Task.detached(priority: .utility) {
                DiffParser.parse(raw).first
            }.value

            guard isCurrentBinding(directory: directory, generation: bindingGeneration),
                  fileSelectionGeneration == selectionGeneration,
                  selectedFile?.path == file.path,
                  selectedFile?.isStaged == file.isStaged else {
                return
            }

            rawDiffContent = raw
            parsedDiff = parsed
            gitError = nil
        } catch {
            guard isCurrentBinding(directory: directory, generation: bindingGeneration),
                  fileSelectionGeneration == selectionGeneration,
                  selectedFile?.path == file.path,
                  selectedFile?.isStaged == file.isStaged else {
                return
            }

            rawDiffContent = ""
            parsedDiff = nil
            gitError = "Diff failed: \(error.localizedDescription)"
        }
    }

    func stage(files: [FileStatus], in directory: String) async throws {
        try await stage(paths: uniquePaths(files.map(\.path)), in: directory)
    }

    func stage(paths: [String], in directory: String) async throws {
        try await gitService.stage(paths: paths, in: directory)
        await refreshAndInvalidateFileList(in: directory, reason: .localGitMutation)
    }

    func unstage(files: [FileStatus], in directory: String) async throws {
        try await unstage(paths: uniquePaths(files.map(\.path)), in: directory)
    }

    func unstage(paths: [String], in directory: String) async throws {
        try await gitService.unstage(paths: paths, in: directory)
        await refreshAndInvalidateFileList(in: directory, reason: .localGitMutation)
    }

    func discard(files: [FileStatus], in directory: String) async throws {
        let stagedFiles = files.filter(\.isStaged)
        let stagedPaths = discardPaths(for: stagedFiles)
        let stagedPathSet = Set(stagedPaths)

        let unstagedPaths = discardPaths(for: files.filter { !$0.isStaged })
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

        stopWatching()
    }

    func handleFSEventsForTesting(changedPaths: Set<String>) {
        fsEventsDidFire(changedPaths: changedPaths)
    }
}

private extension DiffViewerViewModel {
    private func enqueueRefresh(_ request: RefreshRequest) async {
        if let pendingRefresh {
            self.pendingRefresh = pendingRefresh.merged(with: request)
        } else {
            pendingRefresh = request
        }

        while true {
            if inFlightRefresh == nil, let nextRequest = pendingRefresh {
                pendingRefresh = nil
                let refreshID = UUID()
                let task = Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    await self.performRefresh(nextRequest)
                }
                inFlightRefresh = (id: refreshID, task: task)
            }

            guard let inFlightRefresh else {
                return
            }

            let refreshID = inFlightRefresh.id
            let task = inFlightRefresh.task
            await task.value

            if self.inFlightRefresh?.id == refreshID {
                self.inFlightRefresh = nil
            }

            if pendingRefresh == nil {
                return
            }
        }
    }

    private func performRefresh(_ request: RefreshRequest) async {
        if request.invalidatePRCache {
            invalidatePRCache()
        }
        if request.invalidateFileListCache {
            await fileListManager.invalidateCache(for: request.directory)
        }

        let generation = directoryGeneration
        let refreshedFiles: [FileStatus]
        let refreshedError: String?

        do {
            refreshedFiles = try await gitService.status(in: request.directory)
            refreshedError = nil
        } catch {
            refreshedFiles = []
            refreshedError = "Git status failed: \(error.localizedDescription)"
        }

        guard isCurrentBinding(directory: request.directory, generation: generation) else {
            return
        }

        files = refreshedFiles
        gitError = refreshedError

        if refreshedError != nil {
            contextualAction = .none
            return
        }

        let action = await determineAction(in: request.directory)
        guard isCurrentBinding(directory: request.directory, generation: generation) else {
            return
        }

        contextualAction = action
        await refreshSelectedDiffIfNeeded(in: request.directory, generation: generation, reason: request.reason)
    }

    func diffPaths(for file: FileStatus) -> [String] {
        if file.status == .renamed, let originalPath = file.originalPath {
            return [originalPath, file.path]
        }

        return [file.path]
    }

    func discardPaths(for files: [FileStatus]) -> [String] {
        var paths: [String] = []

        for file in files {
            if file.status == .renamed, let originalPath = file.originalPath {
                paths.append(originalPath)
                paths.append(file.path)
            } else {
                paths.append(file.path)
            }
        }

        return uniquePaths(paths)
    }

    func uniquePaths(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        return paths.filter { seen.insert($0).inserted }
    }

    func determineAction(in directory: String) async -> ContextualAction {
        if !files.isEmpty {
            return .commit
        }

        async let aheadTask = (try? await gitService.commitsAheadOfBase(
            baseBranch: baseRef,
            remoteName: remoteName,
            in: directory
        )) ?? 0
        async let currentBranchTask = try? await gitService.currentBranch(in: directory)
        async let prsTask = cachedListPRs(in: directory)

        let ahead = await aheadTask
        let currentBranch = await currentBranchTask
        let prs = await prsTask

        if let pullRequest = prs.first(where: { $0.state == "OPEN" && $0.headRefName == currentBranch }) {
            return .viewPR(url: pullRequest.url)
        }
        if ahead > 0 {
            return .openPR
        }
        return .none
    }

    func refreshSelectedDiffIfNeeded(in directory: String, generation: UInt64, reason: RefreshReason) async {
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
            self.selectedFile = nil
            parsedDiff = nil
            rawDiffContent = ""
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

    func cachedListPRs(in directory: String) async -> [PRInfo] {
        if let cachedPRs,
           Date().timeIntervalSince(prCacheTime) < Self.prCacheTTL {
            return cachedPRs
        }

        do {
            let pullRequests = try await gitHubService.listPRs(in: directory)
            cachedPRs = pullRequests
            prCacheTime = Date()
            return pullRequests
        } catch {
            return cachedPRs ?? []
        }
    }

    func invalidatePRCache() {
        cachedPRs = nil
        prCacheTime = .distantPast
    }

    func isCurrentBinding(directory: String, generation: UInt64) -> Bool {
        activeDirectory == directory && directoryGeneration == generation
    }

    func startWatching(_ directory: String) {
        stopWatching()

        let paths = [directory] as CFArray
        var context = FSEventStreamContext()
        let retainedContext = Unmanaged.passRetained(DiffViewerWatchContext(owner: self, rootDirectory: directory))
        watchContextRetain = retainedContext
        context.info = retainedContext.toOpaque()

        let stream = FSEventStreamCreate(
            nil,
            diffViewerFSEventCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        if let stream {
            let queue = DispatchQueue(label: "com.afollestad.skep.fsevents", qos: .utility)
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
            fsEventStream = stream
            fsEventQueue = queue
        } else {
            retainedContext.release()
            watchContextRetain = nil
        }

        let idlePollInterval = self.idlePollInterval
        pollTask = Task { @MainActor [weak self, idlePollInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: idlePollInterval)
                guard !Task.isCancelled else {
                    break
                }
                guard let self, let directory = self.activeDirectory else {
                    continue
                }
                await self.refresh(in: directory, reason: .idlePoll)
            }
        }
    }

    func stopWatching() {
        debounceTask?.cancel()
        debounceTask = nil
        pollTask?.cancel()
        pollTask = nil

        if let stream = fsEventStream, let queue = fsEventQueue {
            FSEventStreamStop(stream)
            queue.sync {
                FSEventStreamInvalidate(stream)
            }
            FSEventStreamRelease(stream)
            fsEventStream = nil
            fsEventQueue = nil
            watchContextRetain?.release()
            watchContextRetain = nil
        }
    }

    func fsEventsDidFire(changedPaths: Set<String>) {
        debounceTask?.cancel()
        pendingChangedPaths.formUnion(changedPaths)
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: fsEventDebounceDuration)
            guard !Task.isCancelled else {
                return
            }
            guard let activeDirectory else {
                return
            }

            let changedPaths = pendingChangedPaths
            pendingChangedPaths = []
            await refresh(in: activeDirectory, reason: .fsEvent(changedPaths: changedPaths))
        }
    }

    nonisolated static func extractChangedPaths(
        eventPaths: UnsafeMutableRawPointer?,
        count: Int,
        rootDirectory: String?
    ) -> Set<String> {
        guard let rootDirectory,
              let eventPaths else {
            return []
        }

        let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
        let rootPrefix = rootDirectory.hasSuffix("/") ? rootDirectory : rootDirectory + "/"
        return Set(paths.prefix(count).map { absolutePath in
            guard absolutePath.hasPrefix(rootPrefix) else {
                return absolutePath
            }
            return String(absolutePath.dropFirst(rootPrefix.count))
        })
    }

    nonisolated static func handleWatchEventCallback(
        info: UnsafeMutableRawPointer?,
        count: Int,
        eventPaths: UnsafeMutableRawPointer?
    ) {
        guard let info else {
            return
        }

        let watchContext = Unmanaged<DiffViewerWatchContext>.fromOpaque(info).takeUnretainedValue()
        let changedPaths = extractChangedPaths(
            eventPaths: eventPaths,
            count: count,
            rootDirectory: watchContext.rootDirectory
        )

        dispatchWatchEvent(changedPaths: changedPaths, owner: watchContext.owner)
    }

    nonisolated internal static func dispatchWatchEvent(changedPaths: Set<String>, owner: DiffViewerViewModel?) {
        guard let owner else {
            return
        }

        // FSEvents invokes its callback on a dedicated dispatch queue, so the hop back to the
        // main actor must happen from a nonisolated boundary instead of an @MainActor closure.
        Task { @MainActor [weak owner] in
            owner?.fsEventsDidFire(changedPaths: changedPaths)
        }
    }
}

extension Notification.Name {
    static let appWillTerminate = Notification.Name("appWillTerminate")
}
