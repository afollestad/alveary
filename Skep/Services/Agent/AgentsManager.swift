import Foundation

struct AgentEventSubscription: Sendable {
    let generation: UUID
    let stream: AsyncStream<ConversationEvent>
}

protocol AgentsManager: Actor {
    func spawn(id: String, config: AgentSpawnConfig, forkSession: Bool) async throws
    func subscribe(conversationId: String, afterIndex: Int) -> AgentEventSubscription?
    func sendMessage(_ message: String, conversationId: String) async throws
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
    static let agentStatusChanged = Notification.Name("agentStatusChanged")
    static let managedProcessesChanged = Notification.Name("managedProcessesChanged")
}
