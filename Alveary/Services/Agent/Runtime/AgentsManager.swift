import AgentCLIKit
import Foundation

struct AgentEventSubscription: Sendable {
    let generation: UUID
    let stream: AsyncStream<ConversationEvent>
}

struct AgentToolApprovalResolutionRequest: Sendable, Equatable {
    let conversationId: String
    let approval: ToolApprovalRequest
    let resolution: ClaudeToolApprovalResolution
    let additionalApprovals: [ToolApprovalRequest]
    let sessionApproval: AgentSessionApprovalGrant?
    let config: AgentSpawnConfig
}

enum AgentSessionReconfigureResult: Sendable, Equatable {
    case restarted
    case appliedInPlace
    case nextTurnRequired
}

enum AgentOutboundReadiness: Sendable, Equatable {
    case ready
    case respawnRequired
    case blocked(reason: String)
}

protocol AgentsManager: Actor {
    func spawn(id: String, config: AgentSpawnConfig, forkSession: Bool) async throws
    func subscribe(conversationId: String, afterIndex: Int) -> AgentEventSubscription?
    func sendMessage(
        _ message: String,
        conversationId: String,
        activityVisibility: AgentTurnActivityVisibility,
        attachments: [LocalImageAttachment],
        metadata: [String: AgentCLIKit.JSONValue]
    ) async throws
    func sendGoalStartMessage(
        _ message: String,
        initialGoal: String,
        conversationId: String,
        activityVisibility: AgentTurnActivityVisibility,
        attachments: [LocalImageAttachment],
        metadata: [String: AgentCLIKit.JSONValue]
    ) async throws
    func sendSteeringMessage(
        _ message: String,
        conversationId: String,
        steeringInputID: String,
        attachments: [LocalImageAttachment],
        metadata: [String: AgentCLIKit.JSONValue]
    ) async throws
    func resolveToolApproval(_ request: AgentToolApprovalResolutionRequest) async throws -> Bool
    func toolApprovalSelection(providerId: String, conversationId: String, sessionId: String) async -> ToolApprovalSelection?
    func recordToolApprovalSelection(
        _ selection: ToolApprovalSelection,
        providerId: String,
        conversationId: String,
        sessionId: String
    ) async
    func cancelTurn(conversationId: String)
    func destroyRuntime(conversationId: String) async throws
    func kill(conversationId: String)
    func killAll()
    func isRunning(conversationId: String) -> Bool
    func outboundReadiness(conversationId: String) async -> AgentOutboundReadiness
    func hasTrackedProcess(conversationId: String) -> Bool
    func hasInflightLifecycle(conversationId: String) -> Bool
    func startGoal(_ objective: String, conversationId: String) async throws
    func performGoalAction(_ action: AgentCLIKit.AgentGoalAction, conversationId: String) async throws
    @discardableResult
    func reconfigureSession(conversationId: String, config: AgentSpawnConfig) async throws -> AgentSessionReconfigureResult
    func startFreshSession(conversationId: String, config: AgentSpawnConfig) async throws
    func markPersisted(conversationId: String, generation: UUID, upTo index: Int)
    func refreshStatus(conversationId: String) async -> ActivitySignal
    nonisolated func status(for conversationId: String) -> ActivitySignal
    nonisolated var allStatuses: [String: ActivitySignal] { get }
    nonisolated func beginShutdown()
    nonisolated var allProcessesSnapshot: [Process] { get }
}

extension AgentsManager {
    func sendMessage(
        _ message: String,
        conversationId: String,
        activityVisibility: AgentTurnActivityVisibility,
        attachments: [LocalImageAttachment]
    ) async throws {
        try await sendMessage(
            message,
            conversationId: conversationId,
            activityVisibility: activityVisibility,
            attachments: attachments,
            metadata: [:]
        )
    }

    func sendMessage(_ message: String, conversationId: String, activityVisibility: AgentTurnActivityVisibility) async throws {
        try await sendMessage(message, conversationId: conversationId, activityVisibility: activityVisibility, attachments: [], metadata: [:])
    }

    func sendMessage(_ message: String, conversationId: String) async throws {
        try await sendMessage(message, conversationId: conversationId, activityVisibility: .visible, attachments: [])
    }

    func sendGoalStartMessage(
        _ message: String,
        initialGoal: String,
        conversationId: String,
        activityVisibility: AgentTurnActivityVisibility,
        attachments: [LocalImageAttachment],
        metadata: [String: AgentCLIKit.JSONValue]
    ) async throws {
        throw AgentError.spawnFailed("Goal mode is not supported by this agent.")
    }

    func sendGoalStartMessage(
        _ message: String,
        initialGoal: String,
        conversationId: String,
        activityVisibility: AgentTurnActivityVisibility
    ) async throws {
        try await sendGoalStartMessage(
            message,
            initialGoal: initialGoal,
            conversationId: conversationId,
            activityVisibility: activityVisibility,
            attachments: [],
            metadata: [:]
        )
    }

    func sendGoalStartMessage(
        _ message: String,
        initialGoal: String,
        conversationId: String,
        activityVisibility: AgentTurnActivityVisibility,
        attachments: [LocalImageAttachment]
    ) async throws {
        try await sendGoalStartMessage(
            message,
            initialGoal: initialGoal,
            conversationId: conversationId,
            activityVisibility: activityVisibility,
            attachments: attachments,
            metadata: [:]
        )
    }

    func sendSteeringMessage(
        _ message: String,
        conversationId: String,
        steeringInputID: String,
        attachments: [LocalImageAttachment],
        metadata: [String: AgentCLIKit.JSONValue]
    ) async throws {
        try await sendMessage(
            message,
            conversationId: conversationId,
            activityVisibility: .visible,
            attachments: attachments,
            metadata: metadata
        )
    }

    func sendSteeringMessage(_ message: String, conversationId: String, steeringInputID: String) async throws {
        try await sendSteeringMessage(
            message,
            conversationId: conversationId,
            steeringInputID: steeringInputID,
            attachments: [],
            metadata: [:]
        )
    }

    func sendSteeringMessage(
        _ message: String,
        conversationId: String,
        steeringInputID: String,
        attachments: [LocalImageAttachment]
    ) async throws {
        try await sendSteeringMessage(
            message,
            conversationId: conversationId,
            steeringInputID: steeringInputID,
            attachments: attachments,
            metadata: [:]
        )
    }

    func spawn(id: String, config: AgentSpawnConfig) async throws {
        try await spawn(id: id, config: config, forkSession: false)
    }

    func refreshStatus(conversationId: String) async -> ActivitySignal {
        status(for: conversationId)
    }

    func outboundReadiness(conversationId: String) async -> AgentOutboundReadiness {
        isRunning(conversationId: conversationId) ? .ready : .respawnRequired
    }

    func startGoal(_ objective: String, conversationId: String) async throws {
        throw AgentError.spawnFailed("Goal mode is not supported by this agent.")
    }

    func performGoalAction(_ action: AgentCLIKit.AgentGoalAction, conversationId: String) async throws {
        throw AgentError.spawnFailed("Goal \(action.rawValue) is not supported by this agent.")
    }
}

extension Notification.Name {
    // Cross-service notification posted on `NotificationCenter.default`. Any service that changes
    // a conversation's user-visible status — runtime activity from `DefaultAgentsManager` or
    // unread-flag flips from `DefaultNotificationManager` — posts here with `userInfo["conversationId"]`
    // (and optionally `userInfo["signal"]` when the change is a runtime ActivitySignal transition).
    // `SidebarViewModel` and `DiffViewerViewModel` observe it on `.default` to refresh status dots
    // and file-change previews. All posters and observers must stay on `.default` so the bus
    // remains coherent.
    static let agentStatusChanged = Notification.Name("agentStatusChanged")
    static let managedProcessesChanged = Notification.Name("managedProcessesChanged")
}
