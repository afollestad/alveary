import Foundation

struct MCPAgentEntry: Sendable, Equatable {
    let agentId: String
    let name: String
    let config: MCPIntegrationDefinition
}
