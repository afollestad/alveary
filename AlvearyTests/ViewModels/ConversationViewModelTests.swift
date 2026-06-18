import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ConversationViewModelTests: XCTestCase {
    func testReconfigureSessionResetsSubscriptionTrackingAfterSuccessfulUpdate() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.lastObservedEventIndex = 7
        fixture.viewModel.state.lastPersistedEventIndex = 5
        fixture.viewModel.state.activeBufferGeneration = UUID()
        fixture.viewModel.state.activeRuntimeActivityTurnId = "turn-1"

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
        XCTAssertEqual(providerSetupCalls.first?.autoTrust, true)

        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(reconfigureCalls, [.init(conversationId: fixture.conversation.id, config: config)])
        XCTAssertEqual(fixture.viewModel.state.lastObservedEventIndex, 0)
        XCTAssertEqual(fixture.viewModel.state.lastPersistedEventIndex, 0)
        XCTAssertNil(fixture.viewModel.state.activeBufferGeneration)
        XCTAssertNil(fixture.viewModel.state.activeRuntimeActivityTurnId)
        XCTAssertFalse(fixture.viewModel.state.isReconfiguringSession)
    }

    func testReconfigureSessionPreservesSubscriptionTrackingWhenUpdateFails() async throws {
        let fixture = try ConversationViewModelTestFixture(reconfigureError: .reconfigureFailed)
        fixture.viewModel.state.lastObservedEventIndex = 7
        fixture.viewModel.state.lastPersistedEventIndex = 5
        fixture.viewModel.state.activeRuntimeActivityTurnId = "turn-1"

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

        XCTAssertEqual(fixture.viewModel.state.lastObservedEventIndex, 7)
        XCTAssertEqual(fixture.viewModel.state.lastPersistedEventIndex, 5)
        XCTAssertEqual(fixture.viewModel.state.activeRuntimeActivityTurnId, "turn-1")
        XCTAssertFalse(fixture.viewModel.state.isReconfiguringSession)
    }

    func testReconfigureSessionResubscribesWhenRunningUpdateFails() async throws {
        let fixture = try ConversationViewModelTestFixture(
            reconfigureError: .reconfigureFailed,
            initialAgentIsRunning: true
        )
        await fixture.agentsManager.enableSubscription()
        fixture.viewModel.activateViewLifecycle()
        try await waitUntil("expected initial subscription") {
            await fixture.agentsManager.subscribeCalls() == 1
        }
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

        try await waitUntil("expected failed reconfigure to resubscribe") {
            await fixture.agentsManager.subscribeCalls() == 2
        }
        XCTAssertEqual(fixture.viewModel.state.lastObservedEventIndex, 7)
        XCTAssertEqual(fixture.viewModel.state.lastPersistedEventIndex, 5)
        XCTAssertFalse(fixture.viewModel.state.isReconfiguringSession)
    }

    func testSendPersistsRetryableAttemptWhenTransportWriteFails() async throws {
        let fixture = try ConversationViewModelTestFixture(sendError: .sendFailed)

        do {
            try await fixture.viewModel.send("Fix the auth bug")
            XCTFail("Expected send to throw")
        } catch let error as MockAgentsManager.MockError {
            XCTAssertEqual(error, .sendFailed)
        }

        let failedMessage = try XCTUnwrap(try fixture.userMessages().first)
        XCTAssertEqual(failedMessage.content, "Fix the auth bug")
        XCTAssertTrue(fixture.viewModel.state.retryableFailedMessageIDs.contains(failedMessage.id))
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertFalse(fixture.viewModel.state.isSendingMessage)
    }

    func testSteeredConversationPersistsOnlyWhenInputMatchesLocalUserMessage() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.handleEvent(.steeredConversation(inputID: "missing-user-message"))

        XCTAssertTrue(try fixture.records(type: ConversationEventRecord.steeredConversationType).isEmpty)

        let localMessage = fixture.viewModel.insertLocalUserMessage(
            "Focus on tests",
            into: try fixture.dbConversation()
        )
        fixture.viewModel.handleEvent(.steeredConversation(inputID: localMessage.id))
        fixture.viewModel.handleEvent(.steeredConversation(inputID: localMessage.id))

        let markers = try fixture.records(type: ConversationEventRecord.steeredConversationType)
        let marker = try XCTUnwrap(markers.first)
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(marker.id, "steering-\(localMessage.id)")
        XCTAssertEqual(marker.content, ConversationSteering.displayMessage)
        XCTAssertEqual(fixture.viewModel.state.grouper.items.last, .transcriptNote(id: marker.id, kind: .steeredConversation))
    }

    func testSetupAndStartCreatesWorktreeAndStartsInitialPrompt() async throws {
        let worktreeInfo = WorktreeInfo(path: "/tmp/alveary-worktree", branch: "alveary/fix-auth")
        let fixture = try ConversationViewModelTestFixture(
            threadName: "New thread",
            useWorktree: true,
            hasCompletedInitialSetup: false,
            worktreeInfo: worktreeInfo
        )
        fixture.viewModel.state.stagedContext = "Context block"

        try await fixture.viewModel.setupAndStart("Implement the authentication retry flow")

        let refreshedThread = try fixture.dbThread()
        XCTAssertEqual(refreshedThread.worktreePath, worktreeInfo.path)
        XCTAssertEqual(refreshedThread.branch, worktreeInfo.branch)
        XCTAssertTrue(refreshedThread.hasCompletedInitialSetup)
        XCTAssertEqual(refreshedThread.name, "New thread")

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
        XCTAssertEqual(spawnCalls.first?.config.initialPrompt, "Context block\n\nImplement the authentication retry flow")

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Implement the authentication retry flow"])
        XCTAssertNil(fixture.viewModel.state.stagedContext)
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
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
        XCTAssertEqual(refreshedThread.name, "New thread")

        let createCalls = await fixture.worktreeManager.createCalls()
        XCTAssertTrue(createCalls.isEmpty)

        let providerSetupCalls = await fixture.providerSetup.calls()
        XCTAssertEqual(providerSetupCalls.count, 1)
        XCTAssertEqual(providerSetupCalls.first?.providerId, "claude")
        XCTAssertEqual(providerSetupCalls.first?.workingDirectory, fixture.project.path)
        XCTAssertEqual(providerSetupCalls.first?.autoTrust, true)

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertEqual(spawnCalls.count, 1)
        XCTAssertEqual(spawnCalls.first?.config.workingDirectory, fixture.project.path)
        XCTAssertEqual(spawnCalls.first?.config.initialPrompt, "Implement the authentication retry flow")

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Implement the authentication retry flow"])
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
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
        fixture.viewModel.state.stagedContext = "Context block"
        let sendTask = Task {
            try await fixture.viewModel.queueOrSend(message)
        }

        for _ in 0..<50 where fixture.viewModel.setupPhase == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(fixture.viewModel.setupPhase, .creatingWorktree)
        XCTAssertNotNil(fixture.viewModel.initialSetupTask)
        let attemptedMessage = try XCTUnwrap(try fixture.userMessages().first)
        XCTAssertEqual(attemptedMessage.content, message)

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
        XCTAssertEqual(fixture.viewModel.state.stagedContext, "Context block")
        XCTAssertNil(fixture.viewModel.lastTurnError)
        XCTAssertTrue(try fixture.userMessages().isEmpty)
        XCTAssertTrue(fixture.viewModel.state.grouper.items.isEmpty)
        XCTAssertFalse(fixture.viewModel.state.retryableFailedMessageIDs.contains(attemptedMessage.id))
        let refreshedThread = try fixture.dbThread()
        XCTAssertEqual(refreshedThread.name, "New thread")
        XCTAssertFalse(refreshedThread.hasCompletedInitialSetup)
        XCTAssertNil(refreshedThread.worktreePath)
        XCTAssertNil(refreshedThread.branch)
    }

    func testFirstSendSetupFailureKeepsRetryableTranscriptAttempt() async throws {
        let worktreeInfo = WorktreeInfo(path: "/tmp/alveary-worktree", branch: "alveary/fix-auth")
        let fixture = try ConversationViewModelTestFixture(
            threadName: "New thread",
            useWorktree: true,
            hasCompletedInitialSetup: false,
            worktreeInfo: worktreeInfo
        )
        await fixture.worktreeManager.enqueueCreateResult(.failure(.createFailed))

        let message = "Implement the authentication retry flow"
        fixture.viewModel.state.stagedContext = "Context block"
        do {
            try await fixture.viewModel.queueOrSend(message)
            XCTFail("Expected setup to throw")
        } catch let error as MockWorktreeManager.MockError {
            XCTAssertEqual(error, .createFailed)
        }

        let failedMessage = try XCTUnwrap(try fixture.userMessages().first)
        XCTAssertEqual(failedMessage.content, message)
        XCTAssertEqual(try fixture.userMessages().count, 1)
        XCTAssertEqual(fixture.viewModel.state.retryableFailedMessageStagedContexts[failedMessage.id], "Context block")
        XCTAssertTrue(fixture.viewModel.state.retryableFailedMessageIDs.contains(failedMessage.id))
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertNil(fixture.viewModel.state.stagedContext)
        XCTAssertFalse(try fixture.dbThread().hasCompletedInitialSetup)
        XCTAssertNil(fixture.viewModel.setupPhase)

        try await fixture.viewModel.retryFailedUserMessage(id: failedMessage.id)

        let retriedMessages = try fixture.userMessages()
        XCTAssertEqual(retriedMessages.map(\.id), [failedMessage.id])
        XCTAssertEqual(retriedMessages.map(\.content), [message])
        XCTAssertFalse(fixture.viewModel.state.retryableFailedMessageIDs.contains(failedMessage.id))
        XCTAssertNil(fixture.viewModel.state.retryableFailedMessageStagedContexts[failedMessage.id])
        XCTAssertTrue(try fixture.dbThread().hasCompletedInitialSetup)

        let createCalls = await fixture.worktreeManager.createCalls()
        XCTAssertEqual(createCalls.count, 2)
        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertEqual(spawnCalls.count, 1)
        XCTAssertEqual(spawnCalls.first?.config.initialPrompt, "Context block\n\nImplement the authentication retry flow")
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testMakeSpawnConfigPreservesStoredEffortValue() throws {
        let fixture = try ConversationViewModelTestFixture()
        let thread = try fixture.dbThread()
        thread.effort = "auto"

        let config = try fixture.viewModel.makeSpawnConfig()

        XCTAssertEqual(config.effort, "auto")
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
    let keepAwakeService: RecordingKeepAwakeService
    let worktreeManager: MockWorktreeManager
    let providerSetup: MockProviderSetupService
    let contextWindowCache: MockContextWindowCache
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
        reconfigureResult: AgentSessionReconfigureResult = .restarted,
        approvalError: MockAgentsManager.MockError? = nil,
        sessionApprovalEffective: Bool = true,
        worktreeInfo: WorktreeInfo = WorktreeInfo(path: "/tmp/worktree", branch: "alveary/thread"),
        projectIsGitRepository: Bool = true,
        pausesWorktreeCreate: Bool = false,
        initialAgentIsRunning: Bool? = nil,
        providerId: String = "claude",
        threadActivityRecorder: (any ThreadActivityRecording)? = nil
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
        let conversation = Conversation(title: conversationTitle, provider: providerId, thread: thread)
        conversation.pendingRestoreContext = pendingRestoreContext
        project.threads.append(thread); thread.conversations.append(conversation)
        context.insert(project); try context.save()

        let settingsService = InMemorySettingsService(current: Self.testSettings())
        let agentsManager = MockAgentsManager(
            isRunning: initialAgentIsRunning ?? hasCompletedInitialSetup,
            sendError: sendError,
            reconfigureError: reconfigureError,
            reconfigureResult: reconfigureResult,
            approvalError: approvalError,
            sessionApprovalEffective: sessionApprovalEffective
        )
        let runtimeStore = MockConversationRuntimeStore()
        let keepAwakeService = RecordingKeepAwakeService()
        let worktreeManager = MockWorktreeManager(
            worktreeInfo: worktreeInfo,
            blocksCreateUntilCancelled: pausesWorktreeCreate
        )
        let providerSetup = MockProviderSetupService()
        let contextWindowCache = MockContextWindowCache()
        let viewModel = ConversationViewModel(
            conversation: conversation,
            agentsManager: agentsManager,
            runtimeStore: runtimeStore,
            keepAwakeService: keepAwakeService,
            modelContext: context,
            settingsService: settingsService,
            worktreeManager: worktreeManager,
            providerSetup: providerSetup,
            contextWindowCache: contextWindowCache,
            threadActivityRecorder: threadActivityRecorder ?? NoopThreadActivityRecorder()
        )

        self.container = container; self.context = context; self.project = project; self.thread = thread
        self.conversation = conversation; self.agentsManager = agentsManager; self.runtimeStore = runtimeStore
        self.keepAwakeService = keepAwakeService; self.worktreeManager = worktreeManager; self.providerSetup = providerSetup
        self.contextWindowCache = contextWindowCache; self.settingsService = settingsService; self.viewModel = viewModel
    }
    private static func testSettings() -> AppSettings {
        var settings = AppSettings()
        settings.autoTrustProjects = true
        settings.contextManagementEnabled = true
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

    func records(type: String) throws -> [ConversationEventRecord] {
        try context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.conversationId == conversation.id && $0.type == type
        }
    }
}

struct MockContextWindowCacheUpdate: Equatable {
    let providerId: String
    let selectedModel: String
    let reportedModelId: String?
    let contextWindowSize: Int
}

actor MockContextWindowCache: ContextWindowCache {
    private(set) var updates: [MockContextWindowCacheUpdate] = []
    var sizes: [String: Int] = [:]

    func contextWindowSize(providerId: String, model: String) async -> Int? {
        guard let key = JSONContextWindowCache.cacheKey(providerId: providerId, model: model) else {
            return nil
        }
        return sizes[key]
    }

    func update(
        providerId: String,
        selectedModel: String,
        reportedModelId: String?,
        contextWindowSize: Int
    ) async {
        updates.append(MockContextWindowCacheUpdate(
            providerId: providerId,
            selectedModel: selectedModel,
            reportedModelId: reportedModelId,
            contextWindowSize: contextWindowSize
        ))
    }
}
