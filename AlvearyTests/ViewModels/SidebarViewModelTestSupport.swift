import enum AgentCLIKit.JSONValue
import protocol AgentCLIKit.AgentProviderDiscoveryService
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
    let providerSessionActions: RecordingProviderSessionActionService
    let attachmentStore: RecordingConversationAttachmentStore
    let taskWorkspaceOwnershipService: any TaskWorkspaceOwnershipService
    let unexpectedErrors: RecordingUnexpectedErrors
    let notificationManager: RecordingNotificationManager
    let viewModel: SidebarViewModel

    init(
        gitHubInstalledVersion: String? = nil,
        gitHubAuthenticated: Bool = false,
        defaultEffort: String = AppSettings.defaultEffortLevel,
        defaultModel: String = AppSettings.defaultModelValue,
        createWorktreeByDefault: Bool = false,
        providerDiscovery: (any AgentProviderDiscoveryService)? = nil,
        providerSessionActions: RecordingProviderSessionActionService = RecordingProviderSessionActionService(),
        attachmentStore: RecordingConversationAttachmentStore = RecordingConversationAttachmentStore(),
        taskWorkspaceOwnershipService: (any TaskWorkspaceOwnershipService)? = nil,
        saveDraftProjectMove: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        saveDeletionCommit: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        saveThreadCreation: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        savePendingSidebarChanges: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        saveSidebarOrdering: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        invalidateConversationController: @escaping @MainActor (String) -> Void = { _ in },
        unexpectedErrors: RecordingUnexpectedErrors = RecordingUnexpectedErrors()
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
        self.providerSessionActions = providerSessionActions
        self.attachmentStore = attachmentStore
        self.taskWorkspaceOwnershipService = taskWorkspaceOwnershipService ?? makeSidebarTaskWorkspaceService()
        self.unexpectedErrors = unexpectedErrors
        notificationManager = RecordingNotificationManager()

        viewModel = SidebarViewModel(
            agentsManager: agentsManager,
            modelContext: context,
            shell: shell,
            gitHubCLI: gitHubCLI,
            worktreeManager: worktreeManager,
            settingsService: settingsService,
            providerDiscovery: providerDiscovery,
            providerSessionActions: providerSessionActions,
            attachmentStore: attachmentStore,
            taskWorkspaceOwnershipService: self.taskWorkspaceOwnershipService,
            invalidateConversationController: invalidateConversationController,
            saveDraftProjectMove: saveDraftProjectMove,
            saveDeletionCommit: saveDeletionCommit,
            saveThreadCreation: saveThreadCreation,
            savePendingSidebarChanges: savePendingSidebarChanges,
            saveSidebarOrdering: saveSidebarOrdering,
            presentUnexpectedError: { [unexpectedErrors] message in
                unexpectedErrors.present(message)
            },
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
        isDraft: Bool = false,
        archivedAt: Date? = nil,
        provider: String = "claude",
        providerSessionId: String? = nil,
        providerSessionProviderId: String? = nil,
        providerSessionWorkingDirectory: String? = nil,
        modifiedAt: Date? = nil
    ) throws -> AgentThread {
        let project = Project(path: projectPath, name: projectName)
        let thread = AgentThread(
            name: "Thread",
            branch: branch,
            pendingCleanupBranches: pendingCleanupBranches,
            worktreePath: worktreePath,
            hasCompletedInitialSetup: hasCompletedInitialSetup,
            useWorktree: useWorktree,
            isDraft: isDraft,
            modifiedAt: modifiedAt,
            archivedAt: archivedAt,
            project: project
        )
        let conversations = conversationIDs.enumerated().map { index, id in
            Conversation(
                id: id,
                title: id,
                provider: provider,
                providerSessionId: providerSessionId,
                providerSessionProviderId: providerSessionProviderId,
                providerSessionWorkingDirectory: providerSessionWorkingDirectory,
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

    func requireConversation(id: String) throws -> Conversation {
        guard let conversation = context.resolveConversation(conversationID: id) else {
            throw SidebarFixtureError.conversationMissing
        }
        return conversation
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
    case conversationMissing
}

actor SidebarMockAgentsManager: AgentsManager {
    enum MockError: Error, Sendable, Equatable {
        case spawnFailed(String)
        case destroyFailed(String)
    }

    struct SpawnCall: Sendable, Equatable {
        let id: String
        let config: Alveary.AgentSpawnConfig
        let forkSession: Bool
    }

    private let statuses = SidebarLockedStatusStore()
    private var spawnError: MockError?
    private var recordedSpawnCalls: [SpawnCall] = []
    private var spawnObserver: (@Sendable @MainActor (String) -> Void)?
    private var destroyFailures: [String: MockError] = [:]
    private var recordedDestroyCalls: [String] = []
    private var destroyObserver: (@Sendable @MainActor (String) -> Void)?

    func setSpawnError(_ error: MockError?) {
        spawnError = error
    }

    func setDestroyError(_ error: MockError, for conversationId: String) {
        destroyFailures[conversationId] = error
    }

    func setDestroyObserver(_ observer: (@Sendable @MainActor (String) -> Void)?) {
        destroyObserver = observer
    }

    func setSpawnObserver(_ observer: (@Sendable @MainActor (String) -> Void)?) {
        spawnObserver = observer
    }

    func setStatus(_ status: ActivitySignal, for conversationId: String) {
        statuses.set(status, for: conversationId)
    }

    func spawn(id: String, config: Alveary.AgentSpawnConfig, forkSession: Bool) async throws {
        recordedSpawnCalls.append(SpawnCall(id: id, config: config, forkSession: forkSession))
        if let spawnObserver {
            await spawnObserver(id)
        }
        if let spawnError {
            throw spawnError
        }
    }

    func subscribe(conversationId: String, afterIndex: Int) -> Alveary.AgentEventSubscription? {
        nil
    }

    func sendMessage(
        _ message: String,
        conversationId: String,
        activityVisibility: AgentTurnActivityVisibility,
        attachments: [LocalImageAttachment],
        metadata: [String: JSONValue]
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

    func reconfigureSession(
        conversationId: String,
        config: Alveary.AgentSpawnConfig
    ) async throws -> Alveary.AgentSessionReconfigureResult {
        .restarted
    }

    func startFreshSession(conversationId: String, config: Alveary.AgentSpawnConfig) async throws {}

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

    func spawnCalls() -> [SpawnCall] {
        recordedSpawnCalls
    }
}
actor SidebarMockWorktreeManager: WorktreeManager {
    struct CreateCall: Sendable, Equatable {
        let projectPath: String
        let threadName: String
        let baseRef: String?
        let remoteName: String?
    }

    struct PrepareForkContextCall: Sendable, Equatable {
        let sourcePath: String
        let worktreePath: String
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

    private var recordedCreateCalls: [CreateCall] = []
    private var recordedPrepareForkContextCalls: [PrepareForkContextCall] = []
    private var recordedDeleteBranchCalls: [DeleteBranchCall] = []
    private var recordedRemoveCalls: [RemoveCall] = []
    private var recordedRemoveAllCalls: [String] = []
    private var createInfo = WorktreeInfo(path: "/tmp/worktree", branch: "alveary/thread")
    private var createError: MockError?
    private var prepareForkContextError: MockError?
    private var removeError: MockError?
    private var removeAllError: MockError?
    private var listResult: [WorktreeInfo] = []
    private var listError: MockError?

    func setCreateInfo(_ info: WorktreeInfo) {
        createInfo = info
    }

    func setCreateError(_ error: MockError?) {
        createError = error
    }

    func setPrepareForkContextError(_ error: MockError?) {
        prepareForkContextError = error
    }

    func setRemoveError(_ error: MockError?) {
        removeError = error
    }

    func setRemoveAllError(_ error: MockError?) {
        removeAllError = error
    }

    func setListResult(_ result: [WorktreeInfo], error: MockError? = nil) {
        listResult = result
        listError = error
    }

    func create(
        projectPath: String,
        threadName: String,
        baseRef: String?,
        remoteName: String?
    ) async throws -> WorktreeInfo {
        recordedCreateCalls.append(CreateCall(projectPath: projectPath, threadName: threadName, baseRef: baseRef, remoteName: remoteName))
        if let createError {
            throw createError
        }
        return createInfo
    }

    func createFromBranch(
        projectPath: String,
        threadName: String,
        branch: String,
        remoteName: String?
    ) async throws -> WorktreeInfo {
        WorktreeInfo(path: "/tmp/worktree", branch: branch)
    }

    func prepareForkContext(sourcePath: String, worktreePath: String) async throws {
        recordedPrepareForkContextCalls.append(PrepareForkContextCall(sourcePath: sourcePath, worktreePath: worktreePath))
        if let prepareForkContextError {
            throw prepareForkContextError
        }
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
        if let listError {
            throw listError
        }
        return listResult
    }

    func deleteBranchCalls() -> [DeleteBranchCall] {
        recordedDeleteBranchCalls
    }

    func createCalls() -> [CreateCall] {
        recordedCreateCalls
    }

    func prepareForkContextCalls() -> [PrepareForkContextCall] {
        recordedPrepareForkContextCalls
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
}
