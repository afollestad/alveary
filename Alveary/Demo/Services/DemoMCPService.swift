#if DEBUG
import Foundation

/// Serves `DemoCatalogs` instead of the user's real MCP configuration.
///
/// Same safety requirement as `DemoSkillsService`: `DefaultMCPService` writes through the Claude
/// and Codex config stores, so Add Server / Remove Server on the real service would edit the
/// user's `~/.claude.json` and `~/.codex/config.toml` from an otherwise isolated demo profile.
@MainActor
final class DemoMCPService: MCPService {
    private var servers = DemoCatalogs.mcpServers

    func loadAll() async throws -> [MCPServer] {
        servers
    }

    func loadRecommended() async throws -> [RecommendedMCPServer] {
        DemoCatalogs.recommendedMCPServers
    }

    func addServer(_ server: MCPServer, for agents: [String]) async throws {
        var copy = server
        copy.providers = agents
        // `MCPServer.id` is its name, so an edit replaces rather than duplicates.
        if let index = servers.firstIndex(where: { $0.name == server.name }) {
            servers[index] = copy
        } else {
            servers.append(copy)
        }
    }

    func removeServer(_ server: MCPServer) async throws {
        servers.removeAll { $0.name == server.name }
    }

    /// Never empty: the Add/Edit pane's Save gates on a non-empty agent selection. The real
    /// service reaches this through provider detection, which spawns a `--version` probe per
    /// provider; the stub removes that from the screen entirely.
    func availableAgents() async -> [MCPAgentAvailability] {
        DemoCatalogs.mcpAgents
    }
}
#endif
