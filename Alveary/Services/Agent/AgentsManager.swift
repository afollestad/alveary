import Foundation

struct AgentEventSubscription: Sendable {
    let generation: UUID
    let stream: AsyncStream<ConversationEvent>
}

protocol AgentsManager: Actor {
    func spawn(id: String, config: AgentSpawnConfig, forkSession: Bool) async throws
    func subscribe(conversationId: String, afterIndex: Int) -> AgentEventSubscription?
    func sendMessage(_ message: String, conversationId: String) async throws
    func resolveToolApproval(
        conversationId: String,
        approval: ToolApprovalRequest,
        decision: ClaudeToolApprovalDecision,
        sessionApproval: AgentSessionApprovalGrant?,
        config: AgentSpawnConfig
    ) async throws -> Bool
    func cancelTurn(conversationId: String)
    func destroyRuntime(conversationId: String) async throws
    func kill(conversationId: String)
    func killAll()
    func isRunning(conversationId: String) -> Bool
    func hasTrackedProcess(conversationId: String) -> Bool
    func hasInflightLifecycle(conversationId: String) -> Bool
    func reconfigureSession(conversationId: String, config: AgentSpawnConfig) async throws
    func markPersisted(conversationId: String, generation: UUID, upTo index: Int)
    nonisolated func status(for conversationId: String) -> ActivitySignal
    nonisolated var allStatuses: [String: ActivitySignal] { get }
    nonisolated func beginShutdown()
    nonisolated var allProcessesSnapshot: [Process] { get }
}

extension AgentsManager {
    func spawn(id: String, config: AgentSpawnConfig) async throws {
        try await spawn(id: id, config: config, forkSession: false)
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
