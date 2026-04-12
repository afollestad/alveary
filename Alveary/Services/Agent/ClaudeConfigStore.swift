import Foundation

struct ClaudeMCPServerConfig: Codable, Sendable, Equatable {
    var command: String?
    var args: [String]?
    var url: String?
    var headers: [String: String]?
    var env: [String: String]?
}

protocol ClaudeConfigStore: Actor {
    func upsertTrustedProject(path: String) async
    func readMCPServers() async -> [String: ClaudeMCPServerConfig]
    func writeMCPServers(_ servers: [String: ClaudeMCPServerConfig]) async
}
