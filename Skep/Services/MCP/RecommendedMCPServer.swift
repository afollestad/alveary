import Foundation

struct RecommendedMCPServer: Identifiable, Sendable, Equatable {
    var id: String { template.id }

    let template: MCPServer
    let description: String
    let headerPrompts: [String]
}
