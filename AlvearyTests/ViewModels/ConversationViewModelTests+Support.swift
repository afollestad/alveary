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

    struct FreshSessionCall: Sendable, Equatable {
        let conversationId: String
        let config: AgentSpawnConfig
    }

    // swiftlint:disable:next large_tuple
    typealias MarkPersistedCall = (conversationId: String, generation: UUID, index: Int)

    struct ApprovalCall: Sendable, Equatable {
        let conversationId: String
        let approval: ToolApprovalRequest
        let resolution: ClaudeToolApprovalResolution
        let additionalApprovals: [ToolApprovalRequest]
        let sessionApproval: AgentSessionApprovalGrant?
        let config: AgentSpawnConfig

        var decision: ClaudeToolApprovalDecision { resolution.decision }
        var updatedInput: String? { resolution.updatedInput }
    }

    private var isRunningValue: Bool
    private let sendError: MockError?
    private let reconfigureError: MockError?
    private let reconfigureResult: AgentSessionReconfigureResult
    private let approvalError: MockError?
    private let sessionApprovalEffective: Bool
    private let statusStore = MockAgentsManagerStatusStore()
    private var queuedSendResults: [Result<Void, MockError>] = []
    private var queuedRefreshStatuses: [ActivitySignal] = []
    private var pausesNextRefreshStatus = false
    private var refreshStatusContinuation: CheckedContinuation<Void, Never>?
    private var recordedSentMessages: [String] = []
    private var recordedSpawnCalls: [SpawnCall] = []
    private var recordedReconfigureCalls: [ReconfigureCall] = []
    private var recordedFreshSessionCalls: [FreshSessionCall] = []
    private var recordedMarkPersistedCalls: [MarkPersistedCall] = []
    private var recordedApprovalCalls: [ApprovalCall] = []
    private var recordedCancelCalls: [String] = []
    private var recordedRefreshStatusCalls: [String] = []
    private var toolApprovalSelectionStorage: [String: ToolApprovalSelection] = [:]
    private var pausesApprovalResolution = false
    private var approvalResolutionContinuation: CheckedContinuation<Void, Never>?
    private var subscriptionEnabled = false
    private let subscriptionGeneration = UUID()
    private var subscriptionContinuation: AsyncStream<ConversationEvent>.Continuation?
    private var subscribeCallCount = 0
    private var subscriptionTerminationCount = 0

    init(
        isRunning: Bool,
        sendError: MockError?,
        reconfigureError: MockError?,
        reconfigureResult: AgentSessionReconfigureResult = .restarted,
        approvalError: MockError?,
        sessionApprovalEffective: Bool = true
    ) {
        self.isRunningValue = isRunning
        self.sendError = sendError
        self.reconfigureError = reconfigureError
        self.reconfigureResult = reconfigureResult
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

    func resolveToolApproval(_ request: AgentToolApprovalResolutionRequest) async throws -> Bool {
        recordedApprovalCalls.append(
            ApprovalCall(
                conversationId: request.conversationId,
                approval: request.approval,
                resolution: request.resolution,
                additionalApprovals: request.additionalApprovals,
                sessionApproval: request.sessionApproval,
                config: request.config
            )
        )
        await waitForApprovalResolutionIfNeeded()
        if let approvalError {
            throw approvalError
        }
        isRunningValue = true
        return sessionApprovalEffective
    }

    func toolApprovalSelection(
        providerId: String,
        conversationId: String,
        sessionId: String
    ) -> ToolApprovalSelection? {
        toolApprovalSelectionStorage[toolApprovalSelectionKey(
            providerId: providerId,
            conversationId: conversationId,
            sessionId: sessionId
        )]
    }

    func recordToolApprovalSelection(
        _ selection: ToolApprovalSelection,
        providerId: String,
        conversationId: String,
        sessionId: String
    ) {
        toolApprovalSelectionStorage[toolApprovalSelectionKey(
            providerId: providerId,
            conversationId: conversationId,
            sessionId: sessionId
        )] = selection
    }

    func enqueueSendResult(_ result: Result<Void, MockError>) {
        queuedSendResults.append(result)
    }

    func enqueueRefreshStatus(_ status: ActivitySignal) {
        queuedRefreshStatuses.append(status)
    }

    func pauseNextRefreshStatus() {
        pausesNextRefreshStatus = true
    }

    func resumePausedRefreshStatus() {
        pausesNextRefreshStatus = false
        refreshStatusContinuation?.resume()
        refreshStatusContinuation = nil
    }

    func pauseApprovalResolution() {
        pausesApprovalResolution = true
    }

    func resumeApprovalResolution() {
        pausesApprovalResolution = false
        approvalResolutionContinuation?.resume()
        approvalResolutionContinuation = nil
    }

    func isApprovalResolutionPaused() -> Bool {
        approvalResolutionContinuation != nil
    }

    func setStatus(_ status: ActivitySignal, for conversationId: String) {
        statusStore.set(status, for: conversationId)
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

    func cancelTurn(conversationId: String) {
        recordedCancelCalls.append(conversationId)
    }

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

    func reconfigureSession(conversationId: String, config: AgentSpawnConfig) async throws -> AgentSessionReconfigureResult {
        recordedReconfigureCalls.append(ReconfigureCall(conversationId: conversationId, config: config))
        if let reconfigureError {
            throw reconfigureError
        }
        isRunningValue = true
        return reconfigureResult
    }

    func startFreshSession(conversationId: String, config: AgentSpawnConfig) async throws {
        recordedFreshSessionCalls.append(FreshSessionCall(conversationId: conversationId, config: config))
        if let reconfigureError {
            throw reconfigureError
        }
        isRunningValue = true
    }

    func markPersisted(conversationId: String, generation: UUID, upTo index: Int) {
        recordedMarkPersistedCalls.append((conversationId, generation, index))
    }

    func refreshStatus(conversationId: String) async -> ActivitySignal {
        recordedRefreshStatusCalls.append(conversationId)
        if pausesNextRefreshStatus {
            pausesNextRefreshStatus = false
            await withCheckedContinuation { continuation in
                refreshStatusContinuation = continuation
            }
        }
        if !queuedRefreshStatuses.isEmpty {
            statusStore.set(queuedRefreshStatuses.removeFirst(), for: conversationId)
        }
        return statusStore.status(for: conversationId)
    }

    nonisolated func status(for conversationId: String) -> ActivitySignal {
        statusStore.status(for: conversationId)
    }

    nonisolated var allStatuses: [String: ActivitySignal] {
        statusStore.snapshot()
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

    func freshSessionCalls() -> [FreshSessionCall] {
        recordedFreshSessionCalls
    }

    func markPersistedCalls() -> [MarkPersistedCall] {
        recordedMarkPersistedCalls
    }

    func approvalCalls() -> [ApprovalCall] {
        recordedApprovalCalls
    }

    func cancelCalls() -> [String] {
        recordedCancelCalls
    }

    func refreshStatusCalls() -> [String] {
        recordedRefreshStatusCalls
    }

    private func toolApprovalSelectionKey(providerId: String, conversationId: String, sessionId: String) -> String {
        "\(providerId)|\(conversationId)|\(sessionId)"
    }

    private func recordSubscriptionTermination() {
        subscriptionContinuation = nil
        subscriptionTerminationCount += 1
    }

    private func waitForApprovalResolutionIfNeeded() async {
        guard pausesApprovalResolution else {
            return
        }
        await withCheckedContinuation { continuation in
            approvalResolutionContinuation = continuation
        }
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
    enum MockError: Error, Equatable {
        case createFailed
    }

    struct CreateCall: Equatable {
        let projectPath: String
        let threadName: String
        let baseRef: String?
        let remoteName: String?
    }

    private let worktreeInfo: WorktreeInfo
    private var recordedCreateCalls: [CreateCall] = []
    private var queuedCreateResults: [Result<WorktreeInfo, MockError>] = []
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
        if !queuedCreateResults.isEmpty {
            switch queuedCreateResults.removeFirst() {
            case .success(let info):
                return info
            case .failure(let error):
                throw error
            }
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

    func enqueueCreateResult(_ result: Result<WorktreeInfo, MockError>) {
        queuedCreateResults.append(result)
    }
}
