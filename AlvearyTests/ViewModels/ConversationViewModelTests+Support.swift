import Foundation

@testable import Alveary

enum FixtureError: Error {
    case missingThread
    case missingConversation
}

actor MockAgentsManager: AgentsManager {
    enum MockError: Error, Sendable, Equatable {
        case sendFailed
        case reconfigureFailed
        case approvalFailed
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

    struct ApprovalCall: Sendable, Equatable {
        let conversationId: String
        let approval: ToolApprovalRequest
        let resolution: ClaudeToolApprovalResolution
        let sessionApproval: AgentSessionApprovalGrant?
        let config: AgentSpawnConfig

        var decision: ClaudeToolApprovalDecision { resolution.decision }
        var updatedInput: String? { resolution.updatedInput }
    }

    private var isRunningValue: Bool
    private let sendError: MockError?
    private let reconfigureError: MockError?
    private let approvalError: MockError?
    private let sessionApprovalEffective: Bool
    private var queuedSendResults: [Result<Void, MockError>] = []
    private var recordedSentMessages: [String] = []
    private var recordedSpawnCalls: [SpawnCall] = []
    private var recordedReconfigureCalls: [ReconfigureCall] = []
    private var recordedApprovalCalls: [ApprovalCall] = []
    private var subscriptionEnabled = false
    private let subscriptionGeneration = UUID()
    private var subscriptionContinuation: AsyncStream<ConversationEvent>.Continuation?
    private var subscribeCallCount = 0
    private var subscriptionTerminationCount = 0

    init(
        isRunning: Bool,
        sendError: MockError?,
        reconfigureError: MockError?,
        approvalError: MockError?,
        sessionApprovalEffective: Bool = true
    ) {
        self.isRunningValue = isRunning
        self.sendError = sendError
        self.reconfigureError = reconfigureError
        self.approvalError = approvalError
        self.sessionApprovalEffective = sessionApprovalEffective
    }

    func spawn(id: String, config: AgentSpawnConfig, forkSession: Bool) async throws {
        recordedSpawnCalls.append(SpawnCall(id: id, config: config, forkSession: forkSession))
        isRunningValue = true
    }

    func subscribe(conversationId: String, afterIndex: Int) -> AgentEventSubscription? {
        guard subscriptionEnabled else {
            return nil
        }

        subscribeCallCount += 1
        let stream = AsyncStream<ConversationEvent> { continuation in
            subscriptionContinuation = continuation
            continuation.onTermination = { [self] _ in
                Task {
                    await recordSubscriptionTermination()
                }
            }
        }
        return AgentEventSubscription(generation: subscriptionGeneration, stream: stream)
    }

    func sendMessage(_ message: String, conversationId: String) async throws {
        if !queuedSendResults.isEmpty {
            let result = queuedSendResults.removeFirst()
            switch result {
            case .success:
                recordedSentMessages.append(message)
                return
            case .failure(let error):
                throw error
            }
        }

        if let sendError {
            throw sendError
        }
        recordedSentMessages.append(message)
    }

    func resolveToolApproval(
        conversationId: String,
        approval: ToolApprovalRequest,
        resolution: ClaudeToolApprovalResolution,
        sessionApproval: AgentSessionApprovalGrant?,
        config: AgentSpawnConfig
    ) async throws -> Bool {
        recordedApprovalCalls.append(
            ApprovalCall(
                conversationId: conversationId,
                approval: approval,
                resolution: resolution,
                sessionApproval: sessionApproval,
                config: config
            )
        )
        if let approvalError {
            throw approvalError
        }
        isRunningValue = true
        return sessionApprovalEffective
    }

    func enqueueSendResult(_ result: Result<Void, MockError>) {
        queuedSendResults.append(result)
    }

    func enableSubscription() {
        subscriptionEnabled = true
    }

    func yieldSubscriptionEvent(_ event: ConversationEvent) {
        subscriptionContinuation?.yield(event)
    }

    func finishSubscription() {
        subscriptionContinuation?.finish()
        subscriptionContinuation = nil
    }

    func hasActiveSubscription() -> Bool {
        subscriptionContinuation != nil
    }

    func subscribeCalls() -> Int {
        subscribeCallCount
    }

    func subscriptionTerminations() -> Int {
        subscriptionTerminationCount
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

    func approvalCalls() -> [ApprovalCall] {
        recordedApprovalCalls
    }

    private func recordSubscriptionTermination() {
        subscriptionContinuation = nil
        subscriptionTerminationCount += 1
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
    private let blocksCreateUntilCancelled: Bool

    init(worktreeInfo: WorktreeInfo, blocksCreateUntilCancelled: Bool = false) {
        self.worktreeInfo = worktreeInfo
        self.blocksCreateUntilCancelled = blocksCreateUntilCancelled
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
        if blocksCreateUntilCancelled {
            // Sleep long enough that the test is guaranteed to observe the paused state
            // and cancel the setup task. `Task.sleep` throws `CancellationError` once the
            // enclosing task is cancelled, simulating the SIGTERM-then-throw path.
            try await Task.sleep(for: .seconds(60))
        }
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
