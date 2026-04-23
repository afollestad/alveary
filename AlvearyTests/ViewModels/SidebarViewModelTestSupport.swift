import Foundation
import SwiftData

@testable import Alveary

@MainActor
struct SidebarTestFixture {
    let container: ModelContainer
    let context: ModelContext
    let shell: MockShellRunner
    let gitHubCLI: SidebarMockGitHubCLIService
    let agentsManager: SidebarMockAgentsManager
    let worktreeManager: SidebarMockWorktreeManager
    let settingsService: InMemorySettingsService
    let notificationManager: RecordingNotificationManager
    let viewModel: SidebarViewModel

    init(
        gitHubInstalledVersion: String? = nil,
        gitHubAuthenticated: Bool = false,
        defaultEffort: String = AppSettings.defaultEffortLevel,
        defaultModel: String = AppSettings.defaultModelValue,
        createWorktreeByDefault: Bool = false
    ) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            configurations: configuration
        )
        context = ModelContext(container)
        shell = MockShellRunner()
        gitHubCLI = SidebarMockGitHubCLIService(
            installedVersion: gitHubInstalledVersion,
            authenticated: gitHubAuthenticated
        )
        agentsManager = SidebarMockAgentsManager()
        worktreeManager = SidebarMockWorktreeManager()

        var settings = AppSettings()
        settings.effort = defaultEffort
        settings.defaultModel = defaultModel
        settings.createWorktreeByDefault = createWorktreeByDefault
        settingsService = InMemorySettingsService(current: settings)
        notificationManager = RecordingNotificationManager()

        viewModel = SidebarViewModel(
            agentsManager: agentsManager,
            modelContext: context,
            shell: shell,
            gitHubCLI: gitHubCLI,
            worktreeManager: worktreeManager,
            settingsService: settingsService,
            notificationManager: notificationManager
        )
    }

    func insertProject(name: String, path: String) throws -> Project {
        let project = Project(path: path, name: name)
        context.insert(project)
        try context.save()
        return project
    }

    func insertThread(
        projectName: String,
        projectPath: String,
        conversationIDs: [String] = ["main"],
        branch: String? = nil,
        pendingCleanupBranches: [String] = [],
        worktreePath: String? = nil,
        hasCompletedInitialSetup: Bool = false,
        useWorktree: Bool = false,
        archivedAt: Date? = nil
    ) throws -> AgentThread {
        let project = Project(path: projectPath, name: projectName)
        let thread = AgentThread(
            name: "Thread",
            branch: branch,
            pendingCleanupBranches: pendingCleanupBranches,
            worktreePath: worktreePath,
            hasCompletedInitialSetup: hasCompletedInitialSetup,
            useWorktree: useWorktree,
            archivedAt: archivedAt,
            project: project
        )
        let conversations = conversationIDs.enumerated().map { index, id in
            Conversation(
                id: id,
                title: id,
                provider: "claude",
                isMain: index == 0,
                displayOrder: index,
                thread: thread
            )
        }
        thread.conversations = conversations
        project.threads = [thread]
        context.insert(project)
        try context.save()
        return thread
    }

    func requireThread(_ thread: AgentThread) throws -> AgentThread {
        guard let dbThread = context.resolveThread(id: thread.persistentModelID) else {
            throw SidebarFixtureError.threadMissing
        }
        return dbThread
    }

    func threadExists(_ thread: AgentThread) throws -> Bool {
        let descriptor = FetchDescriptor<AgentThread>()
        return try context.fetch(descriptor).contains {
            $0.persistentModelID == thread.persistentModelID
        }
    }

    func markThreadArchived(_ thread: AgentThread) throws {
        let dbThread = try requireThread(thread)
        dbThread.archivedAt = Date()
        try context.save()
    }
}

enum SidebarFixtureError: Error {
    case threadMissing
}

actor SidebarMockAgentsManager: AgentsManager {
    enum MockError: Error, Sendable, Equatable {
        case destroyFailed(String)
    }

    private let statuses = SidebarLockedStatusStore()
    private var destroyFailures: [String: MockError] = [:]
    private var recordedDestroyCalls: [String] = []
    private var destroyObserver: (@Sendable @MainActor (String) -> Void)?

    func setDestroyError(_ error: MockError, for conversationId: String) {
        destroyFailures[conversationId] = error
    }

    func setDestroyObserver(_ observer: (@Sendable @MainActor (String) -> Void)?) {
        destroyObserver = observer
    }

    func setStatus(_ status: ActivitySignal, for conversationId: String) {
        statuses.set(status, for: conversationId)
    }

    func spawn(id: String, config: AgentSpawnConfig, forkSession: Bool) async throws {}

    func subscribe(conversationId: String, afterIndex: Int) -> AgentEventSubscription? {
        nil
    }

    func sendMessage(_ message: String, conversationId: String) async throws {}

    func resolveToolApproval(
        conversationId: String,
        approval: ToolApprovalRequest,
        decision: ClaudeToolApprovalDecision,
        config: AgentSpawnConfig
    ) async throws {}

    func cancelTurn(conversationId: String) {}

    func destroyRuntime(conversationId: String) async throws {
        recordedDestroyCalls.append(conversationId)
        if let destroyObserver {
            await destroyObserver(conversationId)
        }
        if let error = destroyFailures[conversationId] {
            throw error
        }
        statuses.set(.stopped, for: conversationId)
    }

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
        statuses.status(for: conversationId)
    }

    nonisolated var allStatuses: [String: ActivitySignal] {
        statuses.snapshot()
    }

    nonisolated func beginShutdown() {}

    nonisolated var allProcessesSnapshot: [Process] {
        []
    }

    func destroyCalls() -> [String] {
        recordedDestroyCalls
    }
}

actor SidebarMockWorktreeManager: WorktreeManager {
    enum MockError: Error, Sendable, Equatable {
        case removeFailed
        case removeAllFailed
    }

    struct DeleteBranchCall: Sendable, Equatable {
        let projectPath: String
        let branch: String
    }

    struct RemoveCall: Sendable, Equatable {
        let projectPath: String
        let worktreePath: String
        let branch: String?
    }

    private var recordedDeleteBranchCalls: [DeleteBranchCall] = []
    private var recordedRemoveCalls: [RemoveCall] = []
    private var recordedRemoveAllCalls: [String] = []
    private var removeError: MockError?
    private var removeAllError: MockError?

    func setRemoveError(_ error: MockError?) {
        removeError = error
    }

    func setRemoveAllError(_ error: MockError?) {
        removeAllError = error
    }

    func create(
        projectPath: String,
        threadName: String,
        baseRef: String?,
        remoteName: String?
    ) async throws -> WorktreeInfo {
        WorktreeInfo(path: "/tmp/worktree", branch: "alveary/thread")
    }

    func createFromBranch(
        projectPath: String,
        threadName: String,
        branch: String,
        remoteName: String?
    ) async throws -> WorktreeInfo {
        WorktreeInfo(path: "/tmp/worktree", branch: branch)
    }

    func remove(projectPath: String, worktreePath: String, branch: String?) async throws {
        recordedRemoveCalls.append(
            RemoveCall(projectPath: projectPath, worktreePath: worktreePath, branch: branch)
        )
        if let removeError {
            throw removeError
        }
    }

    func removeAll(projectPath: String) async throws {
        recordedRemoveAllCalls.append(projectPath)
        if let removeAllError {
            throw removeAllError
        }
    }

    func deleteBranch(projectPath: String, branch: String) async throws {
        recordedDeleteBranchCalls.append(
            DeleteBranchCall(projectPath: projectPath, branch: branch)
        )
    }

    func list(projectPath: String) async throws -> [WorktreeInfo] {
        []
    }

    func deleteBranchCalls() -> [DeleteBranchCall] {
        recordedDeleteBranchCalls
    }

    func removeCalls() -> [RemoveCall] {
        recordedRemoveCalls
    }

    func removeAllCalls() -> [String] {
        recordedRemoveAllCalls
    }
}

@MainActor
final class SidebarMockGitHubCLIService: GitHubCLIService, @unchecked Sendable {
    private let installedVersion: String?
    private let authenticated: Bool

    private(set) var checkInstalledCallCount = 0
    private(set) var isAuthenticatedCallCount = 0

    init(installedVersion: String?, authenticated: Bool) {
        self.installedVersion = installedVersion
        self.authenticated = authenticated
    }

    func checkInstalled() async -> String? {
        checkInstalledCallCount += 1
        return installedVersion
    }

    func isAuthenticated() async -> Bool {
        isAuthenticatedCallCount += 1
        return authenticated
    }

    func authenticate() async throws -> GitHubDeviceCode {
        throw GitHubError.authParseFailed
    }

    func awaitAuthentication() async throws -> Bool {
        false
    }

    func cancelAuthentication() {}

    func run(args: [String], in directory: String?) async throws -> ShellResult {
        ShellResult(stdout: "", stderr: "", exitCode: 0, stdoutWasTruncated: false, stderrWasTruncated: false)
    }
}

final class SidebarLockedStatusStore: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: ActivitySignal] = [:]

    func set(_ status: ActivitySignal, for conversationId: String) {
        lock.lock()
        values[conversationId] = status
        lock.unlock()
    }

    func status(for conversationId: String) -> ActivitySignal {
        lock.lock()
        let status = values[conversationId] ?? .neutral
        lock.unlock()
        return status
    }

    func snapshot() -> [String: ActivitySignal] {
        lock.lock()
        let snapshot = values
        lock.unlock()
        return snapshot
    }
}
