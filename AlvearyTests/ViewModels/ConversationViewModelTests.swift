import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ConversationViewModelTests: XCTestCase {
    func testReconfigureSessionClearsPermissionBannerAfterSuccessfulUpdate() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.showPermissionBanner = true
        fixture.viewModel.state.lastPermissionDeniedToolNames = ["Write", "Edit"]
        fixture.viewModel.state.lastObservedEventIndex = 7
        fixture.viewModel.state.lastPersistedEventIndex = 5
        fixture.viewModel.state.activeBufferGeneration = UUID()

        let config = AgentSpawnConfig(
            providerId: "claude",
            workingDirectory: fixture.project.path,
            permissionMode: "acceptEdits",
            model: "sonnet",
            effort: "max",
            initialPrompt: nil
        )

        try await fixture.viewModel.reconfigureSession(config: config)

        let providerSetupCalls = await fixture.providerSetup.calls()
        XCTAssertEqual(providerSetupCalls.count, 1)
        XCTAssertEqual(providerSetupCalls.first?.providerId, "claude")
        XCTAssertEqual(providerSetupCalls.first?.workingDirectory, fixture.project.path)
        XCTAssertEqual(providerSetupCalls.first?.autoTrust, false)

        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(reconfigureCalls, [.init(conversationId: fixture.conversation.id, config: config)])
        XCTAssertFalse(fixture.viewModel.state.showPermissionBanner)
        XCTAssertTrue(fixture.viewModel.state.lastPermissionDeniedToolNames.isEmpty)
        XCTAssertEqual(fixture.viewModel.state.lastObservedEventIndex, 0)
        XCTAssertEqual(fixture.viewModel.state.lastPersistedEventIndex, 0)
        XCTAssertNil(fixture.viewModel.state.activeBufferGeneration)
        XCTAssertFalse(fixture.viewModel.state.isReconfiguringSession)
    }

    func testReconfigureSessionPreservesPermissionBannerWhenUpdateFails() async throws {
        let fixture = try ConversationViewModelTestFixture(reconfigureError: .reconfigureFailed)
        fixture.viewModel.state.showPermissionBanner = true
        fixture.viewModel.state.lastPermissionDeniedToolNames = ["Write"]
        fixture.viewModel.state.lastObservedEventIndex = 7
        fixture.viewModel.state.lastPersistedEventIndex = 5

        let config = AgentSpawnConfig(
            providerId: "claude",
            workingDirectory: fixture.project.path,
            permissionMode: "acceptEdits",
            model: nil,
            effort: "max",
            initialPrompt: nil
        )

        do {
            try await fixture.viewModel.reconfigureSession(config: config)
            XCTFail("Expected reconfigure to throw")
        } catch let error as MockAgentsManager.MockError {
            XCTAssertEqual(error, .reconfigureFailed)
        }

        XCTAssertTrue(fixture.viewModel.state.showPermissionBanner)
        XCTAssertEqual(fixture.viewModel.state.lastPermissionDeniedToolNames, ["Write"])
        XCTAssertEqual(fixture.viewModel.state.lastObservedEventIndex, 7)
        XCTAssertEqual(fixture.viewModel.state.lastPersistedEventIndex, 5)
        XCTAssertFalse(fixture.viewModel.state.isReconfiguringSession)
    }

    func testSendDoesNotPersistWhenTransportWriteFails() async throws {
        let fixture = try ConversationViewModelTestFixture(sendError: .sendFailed)

        do {
            try await fixture.viewModel.send("Fix the auth bug")
            XCTFail("Expected send to throw")
        } catch let error as MockAgentsManager.MockError {
            XCTAssertEqual(error, .sendFailed)
        }

        XCTAssertTrue(try fixture.userMessages().isEmpty)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertFalse(fixture.viewModel.state.isSendingMessage)
    }

    func testQueueOrSendWhileBusyCapturesStagedContextAndClearsLiveBanner() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.stagedContext = "Context block"
        fixture.viewModel.turnState.beginTurn()

        try await fixture.viewModel.queueOrSend("Follow-up")

        let queued = try XCTUnwrap(fixture.viewModel.messageQueue.peekNext())
        XCTAssertEqual(queued.text, "Follow-up")
        XCTAssertEqual(queued.stagedContext, "Context block")
        XCTAssertNil(fixture.viewModel.state.stagedContext)
    }

    func testSendPrependsStagedContextOnlyToTransport() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.stagedContext = "Context block"

        try await fixture.viewModel.send("Fix the auth bug")

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["Context block\n\nFix the auth bug"])
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Fix the auth bug"])
        XCTAssertNil(fixture.viewModel.state.stagedContext)
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
    }

    func testSetupAndStartCreatesWorktreeSpawnsAgentAndSendsFirstMessage() async throws {
        let worktreeInfo = WorktreeInfo(path: "/tmp/alveary-worktree", branch: "alveary/fix-auth")
        let fixture = try ConversationViewModelTestFixture(
            threadName: "New thread",
            useWorktree: true,
            hasCompletedInitialSetup: false,
            worktreeInfo: worktreeInfo
        )

        try await fixture.viewModel.setupAndStart("Implement the authentication retry flow")

        let refreshedThread = try fixture.dbThread()
        XCTAssertEqual(refreshedThread.worktreePath, worktreeInfo.path)
        XCTAssertEqual(refreshedThread.branch, worktreeInfo.branch)
        XCTAssertTrue(refreshedThread.hasCompletedInitialSetup)
        XCTAssertEqual(refreshedThread.name, "Implement the authentication retry flow")

        let createCalls = await fixture.worktreeManager.createCalls()
        XCTAssertEqual(createCalls.count, 1)
        XCTAssertEqual(createCalls.first?.projectPath, fixture.project.path)
        XCTAssertEqual(createCalls.first?.threadName, "Implement the authentication retry flow")
        XCTAssertEqual(createCalls.first?.remoteName, fixture.project.remoteName)

        let providerSetupCalls = await fixture.providerSetup.calls()
        XCTAssertEqual(providerSetupCalls.count, 1)
        XCTAssertEqual(providerSetupCalls.first?.providerId, "claude")
        XCTAssertEqual(providerSetupCalls.first?.workingDirectory, worktreeInfo.path)
        XCTAssertEqual(providerSetupCalls.first?.autoTrust, true)

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertEqual(spawnCalls.count, 1)
        XCTAssertEqual(spawnCalls.first?.config.workingDirectory, worktreeInfo.path)

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["Implement the authentication retry flow"])
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Implement the authentication retry flow"])
        XCTAssertNil(fixture.viewModel.setupPhase)
    }

    func testSetupAndStartDisablesWorktreeForNonGitProjects() async throws {
        let fixture = try ConversationViewModelTestFixture(
            threadName: "New thread",
            useWorktree: true,
            hasCompletedInitialSetup: false,
            projectIsGitRepository: false
        )

        try await fixture.viewModel.setupAndStart("Implement the authentication retry flow")

        let refreshedThread = try fixture.dbThread()
        XCTAssertFalse(refreshedThread.useWorktree)
        XCTAssertNil(refreshedThread.worktreePath)
        XCTAssertNil(refreshedThread.branch)
        XCTAssertTrue(refreshedThread.hasCompletedInitialSetup)
        XCTAssertEqual(refreshedThread.name, "Implement the authentication retry flow")

        let createCalls = await fixture.worktreeManager.createCalls()
        XCTAssertTrue(createCalls.isEmpty)

        let providerSetupCalls = await fixture.providerSetup.calls()
        XCTAssertEqual(providerSetupCalls.count, 1)
        XCTAssertEqual(providerSetupCalls.first?.providerId, "claude")
        XCTAssertEqual(providerSetupCalls.first?.workingDirectory, fixture.project.path)
        XCTAssertEqual(providerSetupCalls.first?.autoTrust, false)

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertEqual(spawnCalls.count, 1)
        XCTAssertEqual(spawnCalls.first?.config.workingDirectory, fixture.project.path)

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["Implement the authentication retry flow"])
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Implement the authentication retry flow"])
        XCTAssertNil(fixture.viewModel.setupPhase)
    }
}

@MainActor
struct ConversationViewModelTestFixture {
    let container: ModelContainer
    let context: ModelContext
    let project: Project
    let thread: AgentThread
    let conversation: Conversation
    let agentsManager: MockAgentsManager
    let runtimeStore: MockConversationRuntimeStore
    let worktreeManager: MockWorktreeManager
    let providerSetup: MockProviderSetupService
    let settingsService: InMemorySettingsService
    let viewModel: ConversationViewModel

    init(
        threadName: String = "Thread",
        conversationTitle: String? = nil,
        threadHasCustomName: Bool = false,
        useWorktree: Bool = false,
        hasCompletedInitialSetup: Bool = true,
        sendError: MockAgentsManager.MockError? = nil,
        reconfigureError: MockAgentsManager.MockError? = nil,
        worktreeInfo: WorktreeInfo = WorktreeInfo(path: "/tmp/worktree", branch: "alveary/thread"),
        projectIsGitRepository: Bool = true
    ) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            configurations: configuration
        )
        let context = ModelContext(container)

        let project = Self.makeProject(isGitRepository: projectIsGitRepository)
        let thread = AgentThread(
            name: threadName,
            hasCustomName: threadHasCustomName,
            hasCompletedInitialSetup: hasCompletedInitialSetup,
            useWorktree: useWorktree,
            project: project
        )
        let conversation = Conversation(title: conversationTitle, provider: "claude", thread: thread)
        project.threads.append(thread)
        thread.conversations.append(conversation)
        context.insert(project)
        try context.save()

        let settingsService = InMemorySettingsService(current: Self.testSettings())
        let agentsManager = MockAgentsManager(isRunning: hasCompletedInitialSetup, sendError: sendError, reconfigureError: reconfigureError)
        let runtimeStore = MockConversationRuntimeStore()
        let worktreeManager = MockWorktreeManager(worktreeInfo: worktreeInfo)
        let providerSetup = MockProviderSetupService()
        let viewModel = ConversationViewModel(
            conversation: conversation,
            agentsManager: agentsManager,
            runtimeStore: runtimeStore,
            modelContext: context,
            settingsService: settingsService,
            worktreeManager: worktreeManager,
            providerSetup: providerSetup
        )

        self.container = container
        self.context = context
        self.project = project
        self.thread = thread
        self.conversation = conversation
        self.agentsManager = agentsManager
        self.runtimeStore = runtimeStore
        self.worktreeManager = worktreeManager
        self.providerSetup = providerSetup
        self.settingsService = settingsService
        self.viewModel = viewModel
    }
    private static func testSettings() -> AppSettings {
        var settings = AppSettings()
        settings.autoGenerateNames = true
        settings.autoTrustWorktrees = true
        return settings
    }
    private static func makeProject(isGitRepository: Bool) -> Project {
        Project(
            path: "/tmp/alveary-project",
            name: "Alveary",
            remoteName: isGitRepository ? "origin" : nil,
            gitBranch: isGitRepository ? "feature/auth" : nil,
            baseRef: isGitRepository ? "main" : nil
        )
    }
    func dbThread() throws -> AgentThread {
        guard let thread = context.model(for: self.thread.persistentModelID) as? AgentThread else {
            throw FixtureError.missingThread
        }
        return thread
    }
    func dbConversation() throws -> Conversation {
        guard let conversation = context.model(for: self.conversation.persistentModelID) as? Conversation else {
            throw FixtureError.missingConversation
        }
        return conversation
    }
    func userMessages() throws -> [ConversationEventRecord] {
        try context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.conversationId == conversation.id && $0.role == "user"
        }
    }
}

enum FixtureError: Error {
    case missingThread
    case missingConversation
}

actor MockAgentsManager: AgentsManager {
    enum MockError: Error, Sendable, Equatable {
        case sendFailed
        case reconfigureFailed
    }

    struct SpawnCall: Sendable, Equatable {
        let id: String
        let config: AgentSpawnConfig
        let forkSession: Bool
    }

    struct ReconfigureCall: Sendable, Equatable {
        let conversationId: String
        let config: AgentSpawnConfig
    }

    private var isRunningValue: Bool
    private let sendError: MockError?
    private let reconfigureError: MockError?
    private var recordedSentMessages: [String] = []
    private var recordedSpawnCalls: [SpawnCall] = []
    private var recordedReconfigureCalls: [ReconfigureCall] = []

    init(isRunning: Bool, sendError: MockError?, reconfigureError: MockError?) {
        self.isRunningValue = isRunning
        self.sendError = sendError
        self.reconfigureError = reconfigureError
    }

    func spawn(id: String, config: AgentSpawnConfig, forkSession: Bool) async throws {
        recordedSpawnCalls.append(SpawnCall(id: id, config: config, forkSession: forkSession))
        isRunningValue = true
    }

    func subscribe(conversationId: String, afterIndex: Int) -> AgentEventSubscription? {
        nil
    }

    func sendMessage(_ message: String, conversationId: String) async throws {
        if let sendError {
            throw sendError
        }
        recordedSentMessages.append(message)
    }

    func cancelTurn(conversationId: String) {}
    func destroyRuntime(conversationId: String) async throws {
        isRunningValue = false
    }
    func kill(conversationId: String) {
        isRunningValue = false
    }
    func killAll() {
        isRunningValue = false
    }
    func isRunning(conversationId: String) -> Bool {
        isRunningValue
    }
    func hasTrackedProcess(conversationId: String) -> Bool {
        isRunningValue
    }
    func hasInflightLifecycle(conversationId: String) -> Bool {
        false
    }
    func reconfigureSession(conversationId: String, config: AgentSpawnConfig) async throws {
        recordedReconfigureCalls.append(ReconfigureCall(conversationId: conversationId, config: config))
        if let reconfigureError {
            throw reconfigureError
        }
        isRunningValue = true
    }
    func markPersisted(conversationId: String, generation: UUID, upTo index: Int) {}

    nonisolated func status(for conversationId: String) -> ActivitySignal {
        .neutral
    }

    nonisolated var allStatuses: [String: ActivitySignal] {
        [:]
    }

    nonisolated func beginShutdown() {}

    nonisolated var allProcessesSnapshot: [Process] {
        []
    }

    func sentMessages() -> [String] {
        recordedSentMessages
    }

    func spawnCalls() -> [SpawnCall] {
        recordedSpawnCalls
    }

    func reconfigureCalls() -> [ReconfigureCall] {
        recordedReconfigureCalls
    }
}

@MainActor
final class MockConversationRuntimeStore: ConversationRuntimeStore {
    private var states: [String: ConversationState] = [:]

    func conversationState(for conversationId: String) -> ConversationState {
        if let state = states[conversationId] {
            return state
        }

        let state = ConversationState()
        states[conversationId] = state
        return state
    }
}

actor MockWorktreeManager: WorktreeManager {
    struct CreateCall: Equatable {
        let projectPath: String
        let threadName: String
        let baseRef: String?
        let remoteName: String?
    }

    private let worktreeInfo: WorktreeInfo
    private var recordedCreateCalls: [CreateCall] = []

    init(worktreeInfo: WorktreeInfo) {
        self.worktreeInfo = worktreeInfo
    }

    func create(
        projectPath: String,
        threadName: String,
        baseRef: String?,
        remoteName: String?
    ) async throws -> WorktreeInfo {
        recordedCreateCalls.append(
            CreateCall(
                projectPath: projectPath,
                threadName: threadName,
                baseRef: baseRef,
                remoteName: remoteName
            )
        )
        return worktreeInfo
    }

    func createFromBranch(
        projectPath: String,
        threadName: String,
        branch: String,
        remoteName: String?
    ) async throws -> WorktreeInfo {
        worktreeInfo
    }

    func remove(projectPath: String, worktreePath: String, branch: String?) async throws {}

    func removeAll(projectPath: String) async throws {}

    func deleteBranch(projectPath: String, branch: String) async throws {}

    func list(projectPath: String) async throws -> [WorktreeInfo] {
        []
    }

    func createCalls() -> [CreateCall] {
        recordedCreateCalls
    }
}

actor MockProviderSetupService: ProviderSetupService {
    struct Call: Sendable, Equatable {
        let providerId: String
        let workingDirectory: String
        let autoTrust: Bool
    }

    private var recordedCalls: [Call] = []

    func prepareForSpawn(providerId: String, workingDirectory: String, autoTrust: Bool) async {
        recordedCalls.append(
            Call(
                providerId: providerId,
                workingDirectory: workingDirectory,
                autoTrust: autoTrust
            )
        )
    }

    func calls() -> [Call] {
        recordedCalls
    }
}
