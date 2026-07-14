// swiftlint:disable file_length

import enum AgentCLIKit.AgentGoalAction
import enum AgentCLIKit.JSONValue
import Foundation

@testable import Alveary

enum FixtureError: Error {
    case missingThread
    case missingConversation
}

// swiftlint:disable:next type_body_length
actor MockAgentsManager: AgentsManager {
    enum MockError: Error, Sendable, Equatable { case sendFailed, stdinClosed, reconfigureFailed, approvalFailed }

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

    struct SubscribeCall: Sendable, Equatable { let conversationId: String; let afterIndex: Int }

    struct SteeringCall: Sendable, Equatable {
        let message: String
        let conversationId: String
        let steeringInputID: String
        let attachments: [LocalImageAttachment]
        let metadata: [String: JSONValue]

        init(
            message: String,
            conversationId: String,
            steeringInputID: String,
            attachments: [LocalImageAttachment] = [],
            metadata: [String: JSONValue] = [:]
        ) {
            self.message = message
            self.conversationId = conversationId
            self.steeringInputID = steeringInputID
            self.attachments = attachments
            self.metadata = metadata
        }
    }

    struct GoalStartCall: Sendable, Equatable {
        let message: String
        let initialGoal: String
        let conversationId: String
        let activityVisibility: AgentTurnActivityVisibility
        let attachments: [LocalImageAttachment]
        let metadata: [String: JSONValue]

        init(
            message: String,
            initialGoal: String,
            conversationId: String,
            activityVisibility: AgentTurnActivityVisibility,
            attachments: [LocalImageAttachment] = [],
            metadata: [String: JSONValue] = [:]
        ) {
            self.message = message
            self.initialGoal = initialGoal
            self.conversationId = conversationId
            self.activityVisibility = activityVisibility
            self.attachments = attachments
            self.metadata = metadata
        }
    }

    struct ExistingGoalStartCall: Sendable, Equatable {
        let objective: String
        let conversationId: String
    }

    struct GoalActionCall: Sendable, Equatable {
        let action: AgentGoalAction
        let conversationId: String
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
    private var queuedSpawnErrors: [Error] = []
    private var queuedSendResults: [Result<Void, Error>] = []
    private var queuedDestroyErrors: [Error] = []
    private var queuedOutboundReadiness: [AgentOutboundReadiness] = []
    private var queuedRefreshStatuses: [ActivitySignal] = []
    private var failsSendWhenCurrentTaskIsCancelled = false
    private var failsDestroyWhenCurrentTaskIsCancelled = false
    private var pausesNextSpawn = false
    private var spawnEntered = false
    private var spawnCancellationObserved = false
    private var spawnEntryContinuation: CheckedContinuation<Void, Never>?
    private var spawnCancellationContinuation: CheckedContinuation<Void, Never>?
    private var spawnReleaseContinuation: CheckedContinuation<Void, Never>?
    private var pausesNextRefreshStatus = false
    private var refreshStatusContinuation: CheckedContinuation<Void, Never>?
    private var pausesNextDeferredDiscard = false
    private var deferredDiscardEntered = false
    private var deferredDiscardEntryContinuation: CheckedContinuation<Void, Never>?
    private var deferredDiscardReleaseContinuation: CheckedContinuation<Void, Never>?
    private var recordedSentMessages: [String] = []
    private var recordedSentAttachments: [[LocalImageAttachment]] = []
    private var recordedSentMetadata: [[String: JSONValue]] = []
    private var recordedSendVisibilities: [AgentTurnActivityVisibility] = []
    private var recordedGoalStartCalls: [GoalStartCall] = []
    private var recordedExistingGoalStartCalls: [ExistingGoalStartCall] = []
    private var recordedGoalActionCalls: [GoalActionCall] = []
    private var recordedSteeringCalls: [SteeringCall] = []
    private var recordedSpawnCalls: [SpawnCall] = []
    private var recordedReconfigureCalls: [ReconfigureCall] = []
    private var recordedFreshSessionCalls: [FreshSessionCall] = []
    private var recordedSubscribeCalls: [SubscribeCall] = []
    private var recordedSuspendCalls: [String] = []
    private var recordedDestroyCalls: [String] = []
    private var recordedMarkPersistedCalls: [MarkPersistedCall] = []
    private var recordedApprovalCalls: [ApprovalCall] = []
    private var recordedCancelCalls: [String] = []
    private var recordedDeferredDiscardCalls: [String] = []
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
        if pausesNextSpawn {
            pausesNextSpawn = false
            spawnEntered = true
            spawnEntryContinuation?.resume()
            spawnEntryContinuation = nil
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    spawnReleaseContinuation = continuation
                }
            } onCancel: {
                Task { await self.recordSpawnCancellation() }
            }
        }
        if !queuedSpawnErrors.isEmpty {
            throw queuedSpawnErrors.removeFirst()
        }
        isRunningValue = true
    }

    func subscribe(conversationId: String, afterIndex: Int) -> AgentEventSubscription? {
        recordedSubscribeCalls.append(SubscribeCall(conversationId: conversationId, afterIndex: afterIndex))
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

    func sendMessage(
        _ message: String,
        conversationId: String,
        activityVisibility: AgentTurnActivityVisibility,
        attachments: [LocalImageAttachment],
        metadata: [String: JSONValue]
    ) async throws {
        if failsSendWhenCurrentTaskIsCancelled, Task.isCancelled { throw CancellationError() }
        if !queuedSendResults.isEmpty {
            let result = queuedSendResults.removeFirst()
            switch result {
            case .success:
                recordedSentMessages.append(message)
                recordedSentAttachments.append(attachments)
                recordedSentMetadata.append(metadata)
                recordedSendVisibilities.append(activityVisibility)
                return
            case .failure(let error):
                if let mockError = error as? MockError, mockError == .stdinClosed {
                    throw AgentError.stdinClosed
                }
                throw error
            }
        }

        if let sendError {
            throw sendError
        }
        recordedSentMessages.append(message)
        recordedSentAttachments.append(attachments)
        recordedSentMetadata.append(metadata)
        recordedSendVisibilities.append(activityVisibility)
    }

    func sendGoalStartMessage(_ request: AgentGoalStartMessageRequest) async throws {
        try await sendMessage(
            request.message,
            conversationId: request.conversationId,
            activityVisibility: request.activityVisibility,
            attachments: request.attachments,
            metadata: request.metadata
        )
        recordedGoalStartCalls.append(GoalStartCall(
            message: request.message,
            initialGoal: request.initialGoal,
            conversationId: request.conversationId,
            activityVisibility: request.activityVisibility,
            attachments: request.attachments,
            metadata: request.metadata
        ))
    }

    func sendSteeringMessage(
        _ message: String,
        conversationId: String,
        steeringInputID: String,
        attachments: [LocalImageAttachment],
        metadata: [String: JSONValue]
    ) async throws {
        try await sendMessage(
            message,
            conversationId: conversationId,
            activityVisibility: .visible,
            attachments: attachments,
            metadata: metadata
        )
        recordedSteeringCalls.append(SteeringCall(
            message: message,
            conversationId: conversationId,
            steeringInputID: steeringInputID,
            attachments: attachments,
            metadata: metadata
        ))
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

    func enqueueSendResult(_ result: Result<Void, MockError>) { queuedSendResults.append(result.mapError { $0 as Error }) }

    func enqueueSendError(_ error: Error) { queuedSendResults.append(.failure(error)) }

    func enqueueSpawnError(_ error: Error) { queuedSpawnErrors.append(error) }

    func enqueueDestroyError(_ error: Error) { queuedDestroyErrors.append(error) }

    func enqueueOutboundReadiness(_ readiness: AgentOutboundReadiness) { queuedOutboundReadiness.append(readiness) }

    func enqueueRefreshStatus(_ status: ActivitySignal) { queuedRefreshStatuses.append(status) }

    func failSendWhenCurrentTaskIsCancelled() { failsSendWhenCurrentTaskIsCancelled = true }

    func failDestroyWhenCurrentTaskIsCancelled() { failsDestroyWhenCurrentTaskIsCancelled = true }

    func pauseNextSpawn() {
        pausesNextSpawn = true
        spawnEntered = false
        spawnCancellationObserved = false
    }

    func waitUntilSpawnEntered() async {
        guard !spawnEntered else {
            return
        }
        await withCheckedContinuation { continuation in
            spawnEntryContinuation = continuation
        }
    }

    func waitUntilSpawnCancellationObserved() async {
        guard !spawnCancellationObserved else {
            return
        }
        await withCheckedContinuation { continuation in
            spawnCancellationContinuation = continuation
        }
    }

    func resumePausedSpawn() {
        spawnReleaseContinuation?.resume()
        spawnReleaseContinuation = nil
    }

    func pauseNextRefreshStatus() {
        pausesNextRefreshStatus = true
    }

    func resumePausedRefreshStatus() {
        pausesNextRefreshStatus = false
        refreshStatusContinuation?.resume()
        refreshStatusContinuation = nil
    }

    func pauseNextDeferredDiscard() {
        pausesNextDeferredDiscard = true
        deferredDiscardEntered = false
    }

    func waitUntilDeferredDiscardEntered() async {
        guard !deferredDiscardEntered else {
            return
        }
        await withCheckedContinuation { continuation in
            deferredDiscardEntryContinuation = continuation
        }
    }

    func resumeDeferredDiscard() {
        deferredDiscardReleaseContinuation?.resume()
        deferredDiscardReleaseContinuation = nil
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

    func hasActiveSubscription() -> Bool { subscriptionContinuation != nil }

    func subscribeCalls() -> Int { subscribeCallCount }

    func subscriptionTerminations() -> Int { subscriptionTerminationCount }

    func cancelTurn(conversationId: String) { recordedCancelCalls.append(conversationId) }

    func discardInactiveDeferredInteractionRuntime(conversationId: String) async {
        recordedDeferredDiscardCalls.append(conversationId)
        if pausesNextDeferredDiscard {
            pausesNextDeferredDiscard = false
            deferredDiscardEntered = true
            deferredDiscardEntryContinuation?.resume()
            deferredDiscardEntryContinuation = nil
            await withCheckedContinuation { continuation in
                deferredDiscardReleaseContinuation = continuation
            }
        }
        recordedCancelCalls.append(conversationId)
        recordedSuspendCalls.append(conversationId)
        isRunningValue = false
    }

    func suspendRuntime(conversationId: String) async {
        recordedSuspendCalls.append(conversationId)
        isRunningValue = false
    }

    func destroyRuntime(conversationId: String) async throws {
        if failsDestroyWhenCurrentTaskIsCancelled, Task.isCancelled {
            throw CancellationError()
        }
        recordedDestroyCalls.append(conversationId)
        isRunningValue = false
        if !queuedDestroyErrors.isEmpty {
            throw queuedDestroyErrors.removeFirst()
        }
    }

    func kill(conversationId: String) { isRunningValue = false }

    func killAll() { isRunningValue = false }

    func isRunning(conversationId: String) -> Bool { isRunningValue }

    func outboundReadiness(conversationId: String) async -> AgentOutboundReadiness {
        if !queuedOutboundReadiness.isEmpty {
            return queuedOutboundReadiness.removeFirst()
        }
        return .ready
    }

    func hasTrackedProcess(conversationId: String) -> Bool {
        isRunningValue
    }

    func hasInflightLifecycle(conversationId: String) -> Bool {
        false
    }

    func startGoal(_ objective: String, conversationId: String) async throws {
        if !queuedSendResults.isEmpty {
            let result = queuedSendResults.removeFirst()
            switch result {
            case .success:
                recordedExistingGoalStartCalls.append(.init(objective: objective, conversationId: conversationId))
                return
            case .failure(let error):
                throw error
            }
        }
        if let sendError {
            throw sendError
        }
        recordedExistingGoalStartCalls.append(.init(objective: objective, conversationId: conversationId))
    }

    func performGoalAction(_ action: AgentGoalAction, conversationId: String) async throws {
        if !queuedSendResults.isEmpty {
            let result = queuedSendResults.removeFirst()
            switch result {
            case .success:
                recordedGoalActionCalls.append(.init(action: action, conversationId: conversationId))
                return
            case .failure(let error):
                throw error
            }
        }
        if let sendError {
            throw sendError
        }
        recordedGoalActionCalls.append(.init(action: action, conversationId: conversationId))
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

    func sentMessages() -> [String] { recordedSentMessages }
    func sentAttachments() -> [[LocalImageAttachment]] { recordedSentAttachments }
    func sentMetadata() -> [[String: JSONValue]] { recordedSentMetadata }
    func sendVisibilities() -> [AgentTurnActivityVisibility] { recordedSendVisibilities }
    func goalStartCalls() -> [GoalStartCall] { recordedGoalStartCalls }
    func existingGoalStartCalls() -> [ExistingGoalStartCall] { recordedExistingGoalStartCalls }
    func goalActionCalls() -> [GoalActionCall] { recordedGoalActionCalls }
    func steeringCalls() -> [SteeringCall] { recordedSteeringCalls }
    func spawnCalls() -> [SpawnCall] { recordedSpawnCalls }
    func reconfigureCalls() -> [ReconfigureCall] { recordedReconfigureCalls }
    func freshSessionCalls() -> [FreshSessionCall] { recordedFreshSessionCalls }
    func subscribeCallsList() -> [SubscribeCall] { recordedSubscribeCalls }
    func suspendCalls() -> [String] { recordedSuspendCalls }
    func destroyCalls() -> [String] { recordedDestroyCalls }
    func markPersistedCalls() -> [MarkPersistedCall] { recordedMarkPersistedCalls }
    func approvalCalls() -> [ApprovalCall] { recordedApprovalCalls }
    func cancelCalls() -> [String] { recordedCancelCalls }
    func deferredDiscardCalls() -> [String] { recordedDeferredDiscardCalls }
    func refreshStatusCalls() -> [String] { recordedRefreshStatusCalls }

    private func toolApprovalSelectionKey(providerId: String, conversationId: String, sessionId: String) -> String {
        "\(providerId)|\(conversationId)|\(sessionId)"
    }

    private func recordSubscriptionTermination() {
        subscriptionContinuation = nil
        subscriptionTerminationCount += 1
    }

    private func recordSpawnCancellation() {
        spawnCancellationObserved = true
        spawnCancellationContinuation?.resume()
        spawnCancellationContinuation = nil
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
    private var automatedScheduledRunIDs: Set<String> = []

    func conversationState(for conversationId: String) -> ConversationState {
        if let state = states[conversationId] {
            return state
        }

        let state = ConversationState()
        states[conversationId] = state
        return state
    }

    func bindConversationState(_ state: ConversationState, for conversationId: String) {
        states[conversationId] = state
    }

    func setAutomatedScheduledRunActive(_ active: Bool, runID: String) {
        if active {
            automatedScheduledRunIDs.insert(runID)
        } else {
            automatedScheduledRunIDs.remove(runID)
        }
    }

    func isAutomatedScheduledRunActive(runID: String) -> Bool {
        automatedScheduledRunIDs.contains(runID)
    }

    func removeState(for conversationId: String) {
        states.removeValue(forKey: conversationId)
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

    func validateCreation(
        projectPath: String,
        baseRef: String?,
        remoteName: String?
    ) async throws {}

    func validateCreation(
        projectPath: String,
        baseRef: String?,
        remoteName: String?,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity
    ) async throws {}

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

    func create(
        projectPath: String,
        threadName: String,
        baseRef: String?,
        remoteName: String?,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity
    ) async throws -> IdentityValidatedWorktreeInfo {
        let info = try await create(
            projectPath: projectPath,
            threadName: threadName,
            baseRef: baseRef,
            remoteName: remoteName
        )
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: info.path),
              let systemNumber = attributes[.systemNumber] as? NSNumber,
              let fileNumber = attributes[.systemFileNumber] as? NSNumber else {
            throw MockError.createFailed
        }
        return IdentityValidatedWorktreeInfo(
            info: info,
            sourceProjectIdentity: expectedProjectIdentity,
            worktreeIdentity: TaskWorkspaceFileSystemIdentity(
                systemNumber: systemNumber.uint64Value,
                fileNumber: fileNumber.uint64Value
            )
        )
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
    func remove(
        projectPath: String,
        worktreePath: String,
        branch: String?,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity,
        expectedWorktreeIdentity: TaskWorkspaceFileSystemIdentity?
    ) async throws {}

    func removeAll(projectPath: String) async throws {}

    func deleteBranch(projectPath: String, branch: String, expectedOID: String) async throws {}
    func deleteBranch(
        projectPath: String,
        branch: String,
        expectedOID: String,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity
    ) async throws {}

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
