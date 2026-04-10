import Foundation

struct MCPAgentAvailability: Identifiable, Sendable, Equatable {
    var id: String { agentId }

    let agentId: String
    let name: String
    let supportedTransports: [MCPServer.Transport]
}
