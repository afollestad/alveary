import Foundation

struct ClaudeConfigSnapshot: Sendable, Equatable {
    let revision: Int
    let trustedProjectPaths: Set<String>

    func isTrustedProject(path: String) -> Bool {
        trustedProjectPaths.contains(CanonicalPath.normalize(path))
    }
}

struct ClaudeMCPServerConfig: Codable, Sendable, Equatable {
    var command: String?
    var args: [String]?
    var url: String?
    var headers: [String: String]?
    var env: [String: String]?
}

protocol ClaudeConfigStore: Actor {
    nonisolated func cachedSnapshot() -> ClaudeConfigSnapshot
    func currentSnapshot() async -> ClaudeConfigSnapshot
    func snapshots() async -> AsyncStream<ClaudeConfigSnapshot>
    func isTrustedProject(path: String) async -> Bool
    func upsertTrustedProject(path: String) async
    func readMCPServers() async -> [String: ClaudeMCPServerConfig]
    func writeMCPServers(_ servers: [String: ClaudeMCPServerConfig]) async
}

extension Notification.Name {
    static let claudeConfigChanged = Notification.Name("claudeConfigChanged")
}

enum ClaudeConfigNotificationKey {
    static let snapshot = "snapshot"
}
