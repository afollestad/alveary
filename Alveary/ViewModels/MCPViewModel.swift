import Foundation
import Observation

enum MCPPaneTarget: Hashable {
    case addCustom
    case addRecommended(String)
    case edit(String)
}

struct MCPServerDraft: Equatable {
    var name: String
    var transport: MCPServer.Transport
    var command: String
    var argsText: String
    var url: String
    var headersText: String
    var envText: String
    var selectedAgents: Set<String>

    init(availableAgents: [MCPAgentAvailability]) {
        name = ""
        transport = .stdio
        command = ""
        argsText = ""
        url = ""
        headersText = ""
        envText = ""
        selectedAgents = Set(availableAgents.map(\.agentId))
    }

    init(server: MCPServer) {
        name = server.name
        transport = server.transport
        command = server.command ?? ""
        argsText = server.args?.joined(separator: " ") ?? ""
        url = server.url ?? ""
        headersText = Self.serialize(dictionary: server.headers)
        envText = Self.serialize(dictionary: server.env)
        selectedAgents = Set(server.providers)
    }

    init(recommended: RecommendedMCPServer, availableAgents: [MCPAgentAvailability]) {
        self.init(server: recommended.template)
        if !recommended.headerPrompts.isEmpty {
            headersText = recommended.headerPrompts.map { "\($0)=" }.joined(separator: "\n")
        }
        selectedAgents = Set(availableAgents.filter {
            $0.supportedTransports.contains(recommended.template.transport)
        }.map(\.agentId))
    }

    func makeServer() -> MCPServer {
        let parsedArgs = argsText.split(whereSeparator: \.isWhitespace).map(String.init)

        return MCPServer(
            name: name,
            transport: transport,
            command: command.isEmpty ? nil : command,
            args: parsedArgs.isEmpty ? nil : parsedArgs,
            url: url.isEmpty ? nil : url,
            headers: Self.parse(lines: headersText),
            env: Self.parse(lines: envText),
            providers: Array(selectedAgents).sorted()
        )
    }

    private static func parse(lines: String) -> [String: String]? {
        let pairs = lines
            .split(separator: "\n")
            .compactMap { line -> (String, String)? in
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                guard let key = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !key.isEmpty else {
                    return nil
                }
                let value = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                return (key, value)
            }

        guard !pairs.isEmpty else {
            return nil
        }
        return Dictionary(pairs, uniquingKeysWith: { _, latest in latest })
    }

    private static func serialize(dictionary: [String: String]?) -> String {
        dictionary?
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n") ?? ""
    }
}

struct MCPPaneSession: Equatable {
    let generation: UUID
    var draft: MCPServerDraft
    var errorMessage: String?
    var isSubmitting = false
}

@MainActor
@Observable
final class MCPViewModel {
    private let mcpService: any MCPService

    private(set) var servers: [MCPServer] = []
    private(set) var recommended: [RecommendedMCPServer] = []
    private(set) var availableAgents: [MCPAgentAvailability] = []
    private(set) var activePaneTarget: MCPPaneTarget?
    private(set) var paneSessions: [MCPPaneTarget: MCPPaneSession] = [:]
    private(set) var paneDismissalGeneration = 0
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
        discardSession(for: .edit(server.name))
    }

    func refreshProviders() async {
        await load()
    }

    func requestAddCustom() {
        activate(.addCustom) {
            MCPServerDraft(availableAgents: availableAgents)
        }
    }

    func requestAddRecommended(_ recommended: RecommendedMCPServer) {
        activate(.addRecommended(recommended.id)) {
            MCPServerDraft(recommended: recommended, availableAgents: availableAgents)
        }
    }

    func requestEdit(_ server: MCPServer) {
        activate(.edit(server.name)) {
            MCPServerDraft(server: server)
        }
    }

    func updateActiveDraft(_ draft: MCPServerDraft) {
        guard let target = activePaneTarget,
              var session = paneSessions[target] else {
            return
        }
        session.draft = draft
        session.errorMessage = nil
        paneSessions[target] = session
    }

    func clearActivePaneError() {
        guard let target = activePaneTarget else {
            return
        }
        paneSessions[target]?.errorMessage = nil
    }

    func submitActivePane() async {
        guard let target = activePaneTarget,
              var session = paneSessions[target],
              !session.isSubmitting else {
            return
        }
        let generation = session.generation
        session.isSubmitting = true
        session.errorMessage = nil
        paneSessions[target] = session

        do {
            try await addServer(session.draft.makeServer(), for: Array(session.draft.selectedAgents))
            guard paneSessions[target]?.generation == generation else {
                return
            }
            paneSessions.removeValue(forKey: target)
            if activePaneTarget == target {
                activePaneTarget = nil
                paneDismissalGeneration &+= 1
            }
        } catch {
            guard var liveSession = paneSessions[target],
                  liveSession.generation == generation else {
                return
            }
            liveSession.isSubmitting = false
            liveSession.errorMessage = error.localizedDescription
            paneSessions[target] = liveSession
        }
    }

    func deactivatePane() {
        activePaneTarget = nil
    }

    func dismissActivePane() {
        guard let target = activePaneTarget else {
            return
        }
        discardSession(for: target)
        paneDismissalGeneration &+= 1
    }
}

private extension MCPViewModel {
    func activate(_ target: MCPPaneTarget, makeDraft: () -> MCPServerDraft) {
        if paneSessions[target] == nil {
            paneSessions[target] = MCPPaneSession(generation: UUID(), draft: makeDraft())
        }
        activePaneTarget = target
    }

    func discardSession(for target: MCPPaneTarget) {
        paneSessions.removeValue(forKey: target)
        if activePaneTarget == target {
            activePaneTarget = nil
        }
    }

    var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
