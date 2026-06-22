import Foundation

@testable import Alveary

@MainActor
struct DiffViewerTestFixture {
    let directory = "/tmp/alveary-project"
    let gitService: DiffViewerMockGitService
    let diffStore: DiffWorkspaceStore
    let fileListManager: DiffViewerMockFileListManager
    let agentsManager: DiffViewerMockAgentsManager
    let viewModel: DiffViewerViewModel

    init(
        gitService: DiffViewerMockGitService,
        fileListManager: DiffViewerMockFileListManager = DiffViewerMockFileListManager(),
        agentsManager: DiffViewerMockAgentsManager = DiffViewerMockAgentsManager(),
        loadingIndicatorDelay: Duration = .milliseconds(30),
        fsEventDebounceDuration: Duration = .milliseconds(500),
        idlePollInterval: Duration = .seconds(60)
    ) {
        self.gitService = gitService
        self.diffStore = DiffWorkspaceStore(gitService: gitService, loadingIndicatorDelay: loadingIndicatorDelay)
        self.fileListManager = fileListManager
        self.agentsManager = agentsManager
        self.viewModel = DiffViewerViewModel(
            gitService: gitService,
            diffStore: diffStore,
            fileListManager: fileListManager,
            agentsManager: agentsManager,
            fsEventDebounceDuration: fsEventDebounceDuration,
            idlePollInterval: idlePollInterval
        )
    }
}

actor DiffViewerMockGitService: GitService {
    struct DiffCall: Equatable {
        let paths: [String]
        let scope: DiffScope
        let directory: String
    }

    struct DiscardCall: Equatable {
        let paths: [String]
        let scope: DiscardScope
        let directory: String
    }

    struct PathMutationCall: Equatable {
        let paths: [String]
        let directory: String
    }

    struct CommitDetailCall: Equatable {
        let baseBranch: String
        let remoteName: String?
        let directory: String
    }

    struct CommitDiffCall: Equatable {
        let hash: String
        let directory: String
    }

    struct ImageBlobCall: Equatable {
        let source: GitImageBlobSource
        let maxBytes: Int
        let directory: String
    }

    private var statusResults: [Result<[FileStatus], Error>]
    private var statusDelays: [Duration]
    private var diffStatsResults: [Result<DiffStats, Error>]
    private var diffStatsDelays: [Duration]
    private var diffResultQueue: [Result<String, Error>]
    private var diffResults: [String]
    private var diffDelays: [Duration]
    private var syntheticDiffResults: [String]
    private var syntheticDiffResultQueue: [Result<String, Error>]
    private var imageBlobResults: [Result<Data, Error>]
    private var imageBlobDelays: [Duration]
    private var commitsAheadDetailsResults: [Result<[CommitInfo], Error>]
    private var commitsAheadDetailsDelays: [Duration]
    private var commitDiffResults: [Result<String, Error>]
    private var commitDiffDelays: [Duration]
    private let currentBranchResult: Result<String, Error>
    private let currentHeadHashResult: Result<String, Error>
    private let commitsAheadResult: Result<Int, Error>
    private var recordedStatusCallCount = 0
    private var recordedDiffStatsCallCount = 0
    private var recordedDiffCalls: [DiffCall] = []
    private var recordedSyntheticDiffCalls: [String] = []
    private var recordedCurrentHeadHashCallCount = 0
    private var recordedImageBlobCalls: [ImageBlobCall] = []
    private var recordedStageCalls: [PathMutationCall] = []
    private var recordedUnstageCalls: [PathMutationCall] = []
    private var recordedDiscardCalls: [DiscardCall] = []
    private var recordedCommitsAheadDetailsCalls: [CommitDetailCall] = []
    private var recordedCommitDiffCalls: [CommitDiffCall] = []
    private var onStatus: (@Sendable () -> Void)?

    init(
        statusResults: [Result<[FileStatus], Error>],
        statusDelays: [Duration] = [],
        diffStatsResults: [Result<DiffStats, Error>] = [.success(.empty)],
        diffStatsDelays: [Duration] = [],
        diffResultQueue: [Result<String, Error>] = [],
        diffResults: [String] = [],
        diffDelays: [Duration] = [],
        syntheticDiffResults: [String] = [],
        syntheticDiffResultQueue: [Result<String, Error>] = [],
        imageBlobResults: [Result<Data, Error>] = [],
        imageBlobDelays: [Duration] = [],
        commitsAheadDetailsResults: [Result<[CommitInfo], Error>] = [.success([])],
        commitsAheadDetailsDelays: [Duration] = [],
        commitDiffResults: [Result<String, Error>] = [],
        commitDiffDelays: [Duration] = [],
        currentBranchResult: Result<String, Error> = .success("feature"),
        currentHeadHashResult: Result<String, Error> = .success("abcdef1234567890"),
        commitsAheadResult: Result<Int, Error> = .success(0)
    ) {
        self.statusResults = statusResults
        self.statusDelays = statusDelays
        self.diffStatsResults = diffStatsResults
        self.diffStatsDelays = diffStatsDelays
        self.diffResultQueue = diffResultQueue
        self.diffResults = diffResults
        self.diffDelays = diffDelays
        self.syntheticDiffResults = syntheticDiffResults
        self.syntheticDiffResultQueue = syntheticDiffResultQueue
        self.imageBlobResults = imageBlobResults
        self.imageBlobDelays = imageBlobDelays
        self.commitsAheadDetailsResults = commitsAheadDetailsResults
        self.commitsAheadDetailsDelays = commitsAheadDetailsDelays
        self.commitDiffResults = commitDiffResults
        self.commitDiffDelays = commitDiffDelays
        self.currentBranchResult = currentBranchResult
        self.currentHeadHashResult = currentHeadHashResult
        self.commitsAheadResult = commitsAheadResult
    }

    func status(in directory: String) async throws -> [FileStatus] {
        recordedStatusCallCount += 1
        onStatus?()

        if !statusDelays.isEmpty {
            let delay = statusDelays.removeFirst()
            if delay > .zero {
                try await Task.sleep(for: delay)
            }
        }

        guard !statusResults.isEmpty else {
            return []
        }
        return try statusResults.removeFirst().get()
    }

    func diffStats(in directory: String, knownStatuses: [FileStatus]?) async throws -> DiffStats {
        recordedDiffStatsCallCount += 1
        let result: Result<DiffStats, Error> = diffStatsResults.isEmpty ? .success(.empty) : diffStatsResults.removeFirst()

        if !diffStatsDelays.isEmpty {
            let delay = diffStatsDelays.removeFirst()
            if delay > .zero {
                try await Task.sleep(for: delay)
            }
        }

        return try result.get()
    }

    func setOnStatus(_ handler: (@Sendable () -> Void)?) {
        onStatus = handler
    }

    func diff(paths: [String], scope: DiffScope, in directory: String) async throws -> String {
        recordedDiffCalls.append(DiffCall(paths: paths, scope: scope, directory: directory))
        let result: Result<String, Error> = diffResultQueue.isEmpty
            ? .success(diffResults.isEmpty ? "" : diffResults.removeFirst())
            : diffResultQueue.removeFirst()

        if !diffDelays.isEmpty {
            let delay = diffDelays.removeFirst()
            if delay > .zero {
                try await Task.sleep(for: delay)
            }
        }

        return try result.get()
    }

    func syntheticAddedDiff(for path: String, in directory: String) async throws -> String {
        recordedSyntheticDiffCalls.append(path)
        if !syntheticDiffResultQueue.isEmpty {
            return try syntheticDiffResultQueue.removeFirst().get()
        }
        return syntheticDiffResults.isEmpty ? "" : syntheticDiffResults.removeFirst()
    }

    func stage(paths: [String], in directory: String) async throws {
        recordedStageCalls.append(PathMutationCall(paths: paths, directory: directory))
    }

    func unstage(paths: [String], in directory: String) async throws {
        recordedUnstageCalls.append(PathMutationCall(paths: paths, directory: directory))
    }

    func discard(paths: [String], scope: DiscardScope, in directory: String) async throws {
        recordedDiscardCalls.append(DiscardCall(paths: paths, scope: scope, directory: directory))
    }

    func log(in directory: String, limit: Int) async throws -> [CommitInfo] {
        []
    }

    func currentBranch(in directory: String) async throws -> String {
        try currentBranchResult.get()
    }

    func currentHeadHash(in directory: String) async throws -> String {
        recordedCurrentHeadHashCallCount += 1
        return try currentHeadHashResult.get()
    }

    func listFiles(in directory: String) async throws -> [String] {
        []
    }

    func commitsAheadOfBase(baseBranch: String, remoteName: String?, in directory: String) async throws -> Int {
        try commitsAheadResult.get()
    }

    func commitsAheadOfBaseDetails(baseBranch: String, remoteName: String?, in directory: String) async throws -> [CommitInfo] {
        recordedCommitsAheadDetailsCalls.append(
            CommitDetailCall(baseBranch: baseBranch, remoteName: remoteName, directory: directory)
        )

        if !commitsAheadDetailsDelays.isEmpty {
            let delay = commitsAheadDetailsDelays.removeFirst()
            if delay > .zero {
                try await Task.sleep(for: delay)
            }
        }

        let result: Result<[CommitInfo], Error> = commitsAheadDetailsResults.isEmpty
            ? .success([])
            : commitsAheadDetailsResults.removeFirst()
        return try result.get()
    }

    func diffForCommit(hash: String, in directory: String) async throws -> String {
        recordedCommitDiffCalls.append(CommitDiffCall(hash: hash, directory: directory))
        let result: Result<String, Error> = commitDiffResults.isEmpty ? .success("") : commitDiffResults.removeFirst()

        if !commitDiffDelays.isEmpty {
            let delay = commitDiffDelays.removeFirst()
            if delay > .zero {
                try await Task.sleep(for: delay)
            }
        }

        return try result.get()
    }

    func imageBlob(source: GitImageBlobSource, maxBytes: Int, in directory: String) async throws -> Data {
        recordedImageBlobCalls.append(ImageBlobCall(source: source, maxBytes: maxBytes, directory: directory))
        let result: Result<Data, Error> = imageBlobResults.isEmpty ? .success(Data()) : imageBlobResults.removeFirst()
        if !imageBlobDelays.isEmpty {
            let delay = imageBlobDelays.removeFirst()
            if delay > .zero {
                try await Task.sleep(for: delay)
            }
        }
        return try result.get()
    }

    func diffCalls() -> [DiffCall] {
        recordedDiffCalls
    }

    func syntheticDiffCalls() -> [String] {
        recordedSyntheticDiffCalls
    }

    func currentHeadHashCallCount() -> Int {
        recordedCurrentHeadHashCallCount
    }

    func imageBlobCalls() -> [ImageBlobCall] {
        recordedImageBlobCalls
    }

    func discardCalls() -> [DiscardCall] {
        recordedDiscardCalls
    }

    func stageCalls() -> [PathMutationCall] {
        recordedStageCalls
    }

    func unstageCalls() -> [PathMutationCall] {
        recordedUnstageCalls
    }

    func commitsAheadDetailsCalls() -> [CommitDetailCall] {
        recordedCommitsAheadDetailsCalls
    }

    func commitDiffCalls() -> [CommitDiffCall] {
        recordedCommitDiffCalls
    }

    func statusCallCount() -> Int {
        recordedStatusCallCount
    }

    func diffStatsCallCount() -> Int {
        recordedDiffStatsCallCount
    }
}

actor DiffViewerMockFileListManager: FileListManager {
    private var recordedInvalidatedDirectories: [String] = []

    func files(for projectPath: String) async -> [String] {
        []
    }

    func invalidateCache(for projectPath: String) {
        recordedInvalidatedDirectories.append(projectPath)
    }

    func warmCache(for projectPath: String) async {}

    func invalidatedDirectories() -> [String] {
        recordedInvalidatedDirectories
    }
}

actor DiffViewerMockAgentsManager: AgentsManager {
    private let statuses = LockedState<[String: ActivitySignal]>([:])

    func spawn(id: String, config: AgentSpawnConfig, forkSession: Bool) async throws {}

    func subscribe(conversationId: String, afterIndex: Int) -> AgentEventSubscription? {
        nil
    }

    func sendMessage(
        _ message: String,
        conversationId: String,
        activityVisibility: AgentTurnActivityVisibility
    ) async throws {}

    func resolveToolApproval(_ request: AgentToolApprovalResolutionRequest) async throws -> Bool {
        false
    }

    func toolApprovalSelection(
        providerId: String,
        conversationId: String,
        sessionId: String
    ) async -> ToolApprovalSelection? {
        nil
    }

    func recordToolApprovalSelection(
        _ selection: ToolApprovalSelection,
        providerId: String,
        conversationId: String,
        sessionId: String
    ) async {}

    func cancelTurn(conversationId: String) {}

    func destroyRuntime(conversationId: String) async throws {}

    func kill(conversationId: String) {}

    func killAll() {}

    func isRunning(conversationId: String) -> Bool {
        false
    }

    func hasTrackedProcess(conversationId: String) -> Bool {
        false
    }

    func hasInflightLifecycle(conversationId: String) -> Bool {
        false
    }

    func reconfigureSession(conversationId: String, config: AgentSpawnConfig) async throws -> AgentSessionReconfigureResult {
        .restarted
    }

    func startFreshSession(conversationId: String, config: AgentSpawnConfig) async throws {}

    func markPersisted(conversationId: String, generation: UUID, upTo index: Int) {}

    nonisolated func status(for conversationId: String) -> ActivitySignal {
        statuses.withLock { $0[conversationId] ?? .neutral }
    }

    nonisolated var allStatuses: [String: ActivitySignal] {
        statuses.withLock { $0 }
    }

    nonisolated func beginShutdown() {}

    nonisolated var allProcessesSnapshot: [Process] {
        []
    }
}
