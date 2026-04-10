import Foundation
import Observation

@MainActor
@Observable
final class MCPViewModel {
    private let mcpService: any MCPService

    private(set) var servers: [MCPServer] = []
    private(set) var recommended: [RecommendedMCPServer] = []
    private(set) var availableAgents: [MCPAgentAvailability] = []
    var searchQuery: String = ""

    init(mcpService: any MCPService) {
        self.mcpService = mcpService
    }

    var filteredServers: [MCPServer] {
        let query = normalizedSearchQuery
        guard !query.isEmpty else {
            return servers
        }

        return servers.filter { server in
            server.name.localizedCaseInsensitiveContains(query)
        }
    }

    var filteredRecommended: [RecommendedMCPServer] {
        let query = normalizedSearchQuery
        guard !query.isEmpty else {
            return recommended
        }

        return recommended.filter { entry in
            entry.template.name.localizedCaseInsensitiveContains(query) ||
                entry.description.localizedCaseInsensitiveContains(query) ||
                entry.headerPrompts.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    func load() async {
        servers = (try? await mcpService.loadAll()) ?? []
        recommended = (try? await mcpService.loadRecommended()) ?? []
        availableAgents = await mcpService.availableAgents()
    }

    func addServer(_ server: MCPServer, for agents: [String]) async throws {
        try await mcpService.addServer(server, for: agents)
        await load()
    }

    func removeServer(_ server: MCPServer) async throws {
        try await mcpService.removeServer(server)
        await load()
    }

    func refreshProviders() async {
        await load()
    }
}

private extension MCPViewModel {
    var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
