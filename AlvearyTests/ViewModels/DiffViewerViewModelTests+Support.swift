import Foundation

@testable import Alveary

@MainActor
struct DiffViewerTestFixture {
    let directory = "/tmp/alveary-project"
    let gitService: DiffViewerMockGitService
    let gitHubService: DiffViewerMockGitHubService
    let fileListManager: DiffViewerMockFileListManager
    let agentsManager: DiffViewerMockAgentsManager
    let viewModel: DiffViewerViewModel

    init(
        gitService: DiffViewerMockGitService,
        gitHubService: DiffViewerMockGitHubService = DiffViewerMockGitHubService(),
        fileListManager: DiffViewerMockFileListManager = DiffViewerMockFileListManager(),
        agentsManager: DiffViewerMockAgentsManager = DiffViewerMockAgentsManager(),
        fsEventDebounceDuration: Duration = .milliseconds(500),
        idlePollInterval: Duration = .seconds(60)
    ) {
        self.gitService = gitService
        self.gitHubService = gitHubService
        self.fileListManager = fileListManager
        self.agentsManager = agentsManager
        self.viewModel = DiffViewerViewModel(
            gitService: gitService,
            gitHubService: gitHubService,
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

    private var statusResults: [Result<[FileStatus], Error>]
    private var statusDelays: [Duration]
    private var diffResults: [String]
    private var diffDelays: [Duration]
    private var syntheticDiffResults: [String]
    private let currentBranchResult: Result<String, Error>
    private let commitsAheadResult: Result<Int, Error>
    private var recordedStatusCallCount = 0
    private var recordedDiffCalls: [DiffCall] = []
    private var recordedSyntheticDiffCalls: [String] = []
    private var recordedDiscardCalls: [DiscardCall] = []
    private var onStatus: (@Sendable () -> Void)?

    init(
        statusResults: [Result<[FileStatus], Error>],
        statusDelays: [Duration] = [],
        diffResults: [String] = [],
        diffDelays: [Duration] = [],
        syntheticDiffResults: [String] = [],
        currentBranchResult: Result<String, Error> = .success("feature"),
        commitsAheadResult: Result<Int, Error> = .success(0)
    ) {
        self.statusResults = statusResults
        self.statusDelays = statusDelays
        self.diffResults = diffResults
        self.diffDelays = diffDelays
        self.syntheticDiffResults = syntheticDiffResults
        self.currentBranchResult = currentBranchResult
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

    func setOnStatus(_ handler: (@Sendable () -> Void)?) {
        onStatus = handler
    }

    func diff(paths: [String], scope: DiffScope, in directory: String) async throws -> String {
        recordedDiffCalls.append(DiffCall(paths: paths, scope: scope, directory: directory))
        let result = diffResults.isEmpty ? "" : diffResults.removeFirst()

        if !diffDelays.isEmpty {
            let delay = diffDelays.removeFirst()
            if delay > .zero {
                try await Task.sleep(for: delay)
            }
        }

        return result
    }

    func syntheticAddedDiff(for path: String, in directory: String) async throws -> String {
        recordedSyntheticDiffCalls.append(path)
        return syntheticDiffResults.isEmpty ? "" : syntheticDiffResults.removeFirst()
    }

    func stage(paths: [String], in directory: String) async throws {}

    func unstage(paths: [String], in directory: String) async throws {}

    func discard(paths: [String], scope: DiscardScope, in directory: String) async throws {
        recordedDiscardCalls.append(DiscardCall(paths: paths, scope: scope, directory: directory))
    }

    func log(in directory: String, limit: Int) async throws -> [CommitInfo] {
        []
    }

    func currentBranch(in directory: String) async throws -> String {
        try currentBranchResult.get()
    }

    func listFiles(in directory: String) async throws -> [String] {
        []
    }

    func commitsAheadOfBase(baseBranch: String, remoteName: String?, in directory: String) async throws -> Int {
        try commitsAheadResult.get()
    }

    func diffCalls() -> [DiffCall] {
        recordedDiffCalls
    }

    func syntheticDiffCalls() -> [String] {
        recordedSyntheticDiffCalls
    }

    func discardCalls() -> [DiscardCall] {
        recordedDiscardCalls
    }

    func statusCallCount() -> Int {
        recordedStatusCallCount
    }
}

@MainActor
final class DiffViewerMockGitHubService: GitHubService, @unchecked Sendable {
    private var listPRResults: [[PRInfo]]
    private var recordedListPRCallCount = 0

    init(listPRResults: [[PRInfo]] = [[]]) {
        self.listPRResults = listPRResults
    }

    func listPRs(in directory: String) async throws -> [PRInfo] {
        recordedListPRCallCount += 1
        if !listPRResults.isEmpty {
            return listPRResults.removeFirst()
        }
        return []
    }

    func checkRunStatus(prNumber: Int, in directory: String) async throws -> CIStatus {
        .none
    }

    func checkoutPRBranch(prNumber: Int, branchName: String, in directory: String) async throws {}

    func listPRCallCount() -> Int {
        recordedListPRCallCount
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

    func sendMessage(_ message: String, conversationId: String) async throws {}

    func resolveToolApproval(
        conversationId: String,
        approval: ToolApprovalRequest,
        decision: ClaudeToolApprovalDecision,
        sessionApproval: AgentSessionApprovalGrant?,
        config: AgentSpawnConfig
    ) async throws -> Bool {
        false
    }

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

    func reconfigureSession(conversationId: String, config: AgentSpawnConfig) async throws {}

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
