import Foundation

@MainActor
protocol MCPService: AnyObject, Sendable {
    func loadAll() async throws -> [MCPServer]
    func loadRecommended() async throws -> [RecommendedMCPServer]
    func addServer(_ server: MCPServer, for agents: [String]) async throws
    func removeServer(_ server: MCPServer) async throws
    func availableAgents() async -> [MCPAgentAvailability]
}
