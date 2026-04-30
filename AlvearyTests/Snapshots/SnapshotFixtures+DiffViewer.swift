import XCTest

@testable import Alveary

@MainActor
struct SnapshotDiffViewerFixture {
    let directory = "/tmp/alveary-snapshot-project"
    let gitService: SnapshotMockGitService
    let gitHubService: SnapshotMockGitHubService
    let fileListManager: SnapshotMockFileListManager
    let agentsManager: SnapshotMockAgentsManager
    let viewModel: DiffViewerViewModel

    init(
        gitService: SnapshotMockGitService,
        gitHubService: SnapshotMockGitHubService = SnapshotMockGitHubService(),
        fileListManager: SnapshotMockFileListManager = SnapshotMockFileListManager(),
        agentsManager: SnapshotMockAgentsManager = SnapshotMockAgentsManager()
    ) {
        self.gitService = gitService
        self.gitHubService = gitHubService
        self.fileListManager = fileListManager
        self.agentsManager = agentsManager
        viewModel = DiffViewerViewModel(
            gitService: gitService,
            gitHubService: gitHubService,
            fileListManager: fileListManager,
            agentsManager: agentsManager,
            fsEventDebounceDuration: .seconds(10),
            idlePollInterval: .seconds(10)
        )
    }
}

actor SnapshotMockGitService: GitService {
    private var statusResults: [[FileStatus]]
    private var diffStatsResults: [DiffStats]
    private var diffResults: [String]
    private var syntheticDiffResults: [String]

    init(
        statusResults: [[FileStatus]],
        diffStatsResults: [DiffStats] = [.empty],
        diffResults: [String],
        syntheticDiffResults: [String] = []
    ) {
        self.statusResults = statusResults
        self.diffStatsResults = diffStatsResults
        self.diffResults = diffResults
        self.syntheticDiffResults = syntheticDiffResults
    }

    func status(in directory: String) async throws -> [FileStatus] {
        if statusResults.isEmpty {
            return []
        }
        return statusResults.removeFirst()
    }

    func diffStats(in directory: String, knownStatuses: [FileStatus]?) async throws -> DiffStats {
        if diffStatsResults.isEmpty {
            return .empty
        }
        return diffStatsResults.removeFirst()
    }

    func diff(paths: [String], scope: DiffScope, in directory: String) async throws -> String {
        if diffResults.isEmpty {
            return ""
        }
        return diffResults.removeFirst()
    }

    func syntheticAddedDiff(for path: String, in directory: String) async throws -> String {
        if syntheticDiffResults.isEmpty {
            return ""
        }
        return syntheticDiffResults.removeFirst()
    }

    func stage(paths: [String], in directory: String) async throws {}

    func unstage(paths: [String], in directory: String) async throws {}

    func discard(paths: [String], scope: DiscardScope, in directory: String) async throws {}

    func log(in directory: String, limit: Int) async throws -> [CommitInfo] {
        []
    }

    func currentBranch(in directory: String) async throws -> String {
        "feature/chat-input"
    }

    func listFiles(in directory: String) async throws -> [String] {
        []
    }

    func commitsAheadOfBase(baseBranch: String, remoteName: String?, in directory: String) async throws -> Int {
        0
    }

    func commitsAheadOfBaseDetails(baseBranch: String, remoteName: String?, in directory: String) async throws -> [CommitInfo] {
        []
    }

    func diffForCommit(hash: String, in directory: String) async throws -> String {
        ""
    }
}

@MainActor
final class SnapshotMockGitHubService: GitHubService, @unchecked Sendable {
    func listPRs(in directory: String) async throws -> [PRInfo] {
        []
    }

    func checkRunStatus(prNumber: Int, in directory: String) async throws -> CIStatus {
        .none
    }

    func checkoutPRBranch(prNumber: Int, branchName: String, in directory: String) async throws {}
}

actor SnapshotMockFileListManager: FileListManager {
    func files(for projectPath: String) async -> [String] {
        []
    }

    func invalidateCache(for projectPath: String) {}

    func warmCache(for projectPath: String) async {}
}

actor SnapshotMockAgentsManager: AgentsManager {
    private let statusStore = LockedState([String: ActivitySignal]())

    nonisolated func status(for conversationId: String) -> ActivitySignal {
        statusStore.withLock { $0[conversationId] ?? .neutral }
    }

    nonisolated var allStatuses: [String: ActivitySignal] {
        statusStore.withLock { $0 }
    }

    nonisolated func beginShutdown() {}

    nonisolated var allProcessesSnapshot: [Process] {
        []
    }

    func spawn(id: String, config: AgentSpawnConfig, forkSession: Bool) async throws {}

    func subscribe(conversationId: String, afterIndex: Int) -> AgentEventSubscription? {
        nil
    }

    func sendMessage(_ message: String, conversationId: String) async throws {}

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

    func reconfigureSession(conversationId: String, config: AgentSpawnConfig) async throws {}

    func startFreshSession(conversationId: String, config: AgentSpawnConfig) async throws {}

    func markPersisted(conversationId: String, generation: UUID, upTo index: Int) {}

    func setStatus(_ status: ActivitySignal, for conversationId: String) {
        statusStore.withLock { $0[conversationId] = status }
    }
}
