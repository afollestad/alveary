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

    func testCancelDuringInitialSetupRollsBackStateAndRestoresDraft() async throws {
        let fixture = try ConversationViewModelTestFixture(
            threadName: "New thread",
            useWorktree: true,
            hasCompletedInitialSetup: false,
            pausesWorktreeCreate: true
        )

        let message = "Start working on the authentication retry flow"
        let sendTask = Task {
            try await fixture.viewModel.queueOrSend(message)
        }

        for _ in 0..<50 where fixture.viewModel.setupPhase == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(fixture.viewModel.setupPhase, .creatingWorktree)
        XCTAssertNotNil(fixture.viewModel.initialSetupTask)

        await fixture.viewModel.cancel()

        do {
            try await sendTask.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // expected
        }

        XCTAssertNil(fixture.viewModel.setupPhase)
        XCTAssertFalse(fixture.viewModel.state.isCancellingInitialSetup)
        XCTAssertNil(fixture.viewModel.initialSetupTask)
        XCTAssertEqual(fixture.viewModel.state.inputDraft, message)
        XCTAssertNil(fixture.viewModel.lastTurnError)
        let refreshedThread = try fixture.dbThread()
        XCTAssertFalse(refreshedThread.hasCompletedInitialSetup)
        XCTAssertNil(refreshedThread.worktreePath)
        XCTAssertNil(refreshedThread.branch)
    }

    func testMakeSpawnConfigNormalizesLegacyAutomaticEffortToMedium() throws {
        let fixture = try ConversationViewModelTestFixture()
        let thread = try fixture.dbThread()
        thread.effort = "auto"

        let config = try fixture.viewModel.makeSpawnConfig()

        XCTAssertEqual(config.effort, AppSettings.defaultEffortLevel)
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
        pendingRestoreContext: String? = nil,
        sendError: MockAgentsManager.MockError? = nil,
        reconfigureError: MockAgentsManager.MockError? = nil,
        worktreeInfo: WorktreeInfo = WorktreeInfo(path: "/tmp/worktree", branch: "alveary/thread"),
        projectIsGitRepository: Bool = true,
        pausesWorktreeCreate: Bool = false,
        initialAgentIsRunning: Bool? = nil
    ) throws {
        let (container, context) = try Self.makeInMemoryContainer()

        let project = Self.makeProject(isGitRepository: projectIsGitRepository)
        let thread = AgentThread(
            name: threadName,
            hasCustomName: threadHasCustomName,
            hasCompletedInitialSetup: hasCompletedInitialSetup,
            useWorktree: useWorktree,
            project: project
        )
        let conversation = Conversation(title: conversationTitle, provider: "claude", thread: thread)
        conversation.pendingRestoreContext = pendingRestoreContext
        project.threads.append(thread)
        thread.conversations.append(conversation)
        context.insert(project)
        try context.save()

        let settingsService = InMemorySettingsService(current: Self.testSettings())
        let agentsManager = MockAgentsManager(
            isRunning: initialAgentIsRunning ?? hasCompletedInitialSetup,
            sendError: sendError,
            reconfigureError: reconfigureError
        )
        let runtimeStore = MockConversationRuntimeStore()
        let worktreeManager = MockWorktreeManager(
            worktreeInfo: worktreeInfo,
            blocksCreateUntilCancelled: pausesWorktreeCreate
        )
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

    private static func makeInMemoryContainer() throws -> (ModelContainer, ModelContext) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            configurations: configuration
        )
        return (container, ModelContext(container))
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
