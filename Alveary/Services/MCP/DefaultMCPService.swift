import AgentCLIKit
import Foundation

@MainActor
final class DefaultMCPService: MCPService {
    private struct RecommendedMCPEntry: Decodable {
        let name: String
        let description: String
        let transport: String
        let url: String?
        let command: String?
        let args: [String]?
        let headers: [String]?
    }

    private let claudeConfigStore: AgentCLIKit.ClaudeConfigStore
    private let codexConfigStore: AgentCLIKit.CodexConfigStore
    private let providerDetection: ProviderDetectionService
    private let agentRegistry: AgentRegistry
    private let bundle: Bundle

    init(
        claudeConfigStore: AgentCLIKit.ClaudeConfigStore,
        codexConfigStore: AgentCLIKit.CodexConfigStore,
        providerDetection: ProviderDetectionService,
        agentRegistry: AgentRegistry,
        bundle: Bundle = .main
    ) {
        self.claudeConfigStore = claudeConfigStore
        self.codexConfigStore = codexConfigStore
        self.providerDetection = providerDetection
        self.agentRegistry = agentRegistry
        self.bundle = bundle
    }

    func loadAll() async throws -> [MCPServer] {
        var serversByName: [String: (server: MCPServer, providers: Set<String>)] = [:]

        for agent in mcpAgents {
            let rawServers = (try? await readRawServers(for: agent)) ?? [:]
            let adapter = MCPAdapterType(rawValue: agent.config.adapterId) ?? .passthrough
            let canonicalServers = MCPAdapter.adaptReverse(adapter, servers: rawServers)

            for (name, rawEntry) in canonicalServers {
                if var existing = serversByName[name] {
                    existing.providers.insert(agent.agentId)
                    serversByName[name] = existing
                    continue
                }

                let transport: MCPServer.Transport = {
                    if rawEntry["type"] as? String == "http" || (rawEntry["url"] != nil && rawEntry["command"] == nil) {
                        return .http
                    }
                    return .stdio
                }()

                let server = MCPServer(
                    name: name,
                    transport: transport,
                    command: rawEntry["command"] as? String,
                    args: rawEntry["args"] as? [String],
                    url: rawEntry["url"] as? String,
                    headers: rawEntry["headers"] as? [String: String],
                    env: rawEntry["env"] as? [String: String],
                    providers: [agent.agentId]
                )
                serversByName[name] = (server, [agent.agentId])
            }
        }

        return serversByName.values.map { value in
            var server = value.server
            server.providers = Array(value.providers).sorted()
            return server
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func loadRecommended() async throws -> [RecommendedMCPServer] {
        guard let resourceURL = bundle.url(forResource: "mcp-recommended", withExtension: "json"),
              let data = try? Data(contentsOf: resourceURL),
              let entries = try? JSONDecoder().decode([RecommendedMCPEntry].self, from: data) else {
            return []
        }

        let installedServers = (try? await loadAll()) ?? []
        let installedNames = Set(installedServers.map(\.name))
        return entries.compactMap { entry in
            guard !installedNames.contains(entry.name) else {
                return nil
            }

            return RecommendedMCPServer(
                template: MCPServer(
                    name: entry.name,
                    transport: entry.transport == MCPServer.Transport.http.rawValue ? .http : .stdio,
                    command: entry.command,
                    args: entry.args,
                    url: entry.url,
                    headers: nil,
                    env: nil,
                    providers: []
                ),
                description: entry.description,
                headerPrompts: entry.headers ?? []
            )
        }
        .sorted { $0.template.name.localizedCaseInsensitiveCompare($1.template.name) == .orderedAscending }
    }

    func addServer(_ server: MCPServer, for agents: [String]) async throws {
        let selectedAgents = Set(agents)
        let rawServer = mcpServerToRaw(server)
        var pendingWrites: [(entry: MCPAgentEntry, servers: ServerMap)] = []

        for agent in mcpAgents {
            var existingServers = (try? await readRawServers(for: agent)) ?? [:]
            if selectedAgents.contains(agent.agentId), supports(server: server, on: agent) {
                let adapter = MCPAdapterType(rawValue: agent.config.adapterId) ?? .passthrough
                let adapted = MCPAdapter.adaptForward(adapter, servers: [server.name: rawServer])
                if let adaptedEntry = adapted[server.name] {
                    existingServers[server.name] = adaptedEntry
                }
                pendingWrites.append((agent, existingServers))
            } else if existingServers[server.name] != nil {
                existingServers.removeValue(forKey: server.name)
                pendingWrites.append((agent, existingServers))
            }
        }

        for pendingWrite in pendingWrites {
            try await writeRawServers(pendingWrite.servers, to: pendingWrite.entry)
        }
    }

    func removeServer(_ server: MCPServer) async throws {
        for agent in mcpAgents {
            var existingServers = (try? await readRawServers(for: agent)) ?? [:]
            guard existingServers[server.name] != nil else {
                continue
            }

            existingServers.removeValue(forKey: server.name)
            try await writeRawServers(existingServers, to: agent)
        }
    }

    func availableAgents() async -> [MCPAgentAvailability] {
        await providerDetection.checkAllProviders()

        var available: [MCPAgentAvailability] = []
        for agent in mcpAgents {
            let status = await providerDetection.status(for: agent.agentId)
            switch status {
            case .connected, .needsKey, .error:
                let supportedTransports: [MCPServer.Transport] = agent.config.supportsHttp ? [.stdio, .http] : [.stdio]
                available.append(
                    MCPAgentAvailability(
                        agentId: agent.agentId,
                        name: agent.name,
                        supportedTransports: supportedTransports
                    )
                )
            case .missing, .unchecked:
                break
            }
        }

        return available.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private extension DefaultMCPService {
    var mcpAgents: [MCPAgentEntry] {
        agentRegistry.agents.compactMap { agent in
            guard let config = agent.mcp else {
                return nil
            }
            return MCPAgentEntry(agentId: agent.id, name: agent.name, config: config)
        }
    }

    func supports(server: MCPServer, on agent: MCPAgentEntry) -> Bool {
        switch server.transport {
        case .stdio:
            return true
        case .http:
            return agent.config.supportsHttp
        }
    }

    func readRawServers(for agent: MCPAgentEntry) async throws -> ServerMap {
        switch agent.agentId {
        case "claude":
            return try await readClaudeRawServers()
        case "codex":
            return try await readCodexRawServers()
        default:
            return try MCPConfigIO.readServers(from: agent.config)
        }
    }

    func writeRawServers(_ servers: ServerMap, to agent: MCPAgentEntry) async throws {
        if agent.agentId == "claude" {
            let claudeServers = servers.mapValues { server in
                AgentCLIKit.ClaudeMCPServerConfig(
                    command: server["command"] as? String,
                    args: server["args"] as? [String],
                    url: server["url"] as? String,
                    headers: server["headers"] as? [String: String],
                    env: server["env"] as? [String: String],
                    disabled: server["disabled"] as? Bool
                )
            }
            try await claudeConfigStore.writeMCPServers(claudeServers)
            return
        }
        if agent.agentId == "codex" {
            let codexServers = servers.mapValues { server in
                AgentCLIKit.CodexMCPServerConfig(
                    command: server["command"] as? String,
                    args: server["args"] as? [String],
                    env: server["env"] as? [String: String],
                    url: server["url"] as? String,
                    httpHeaders: server["headers"] as? [String: String],
                    enabled: (server["disabled"] as? Bool).map { !$0 }
                )
            }
            try await codexConfigStore.writeMCPServers(codexServers)
            return
        }

        try MCPConfigIO.writeServers(to: agent.config, servers: servers)
    }

    func mcpServerToRaw(_ server: MCPServer) -> RawServerEntry {
        var raw: RawServerEntry = [:]

        switch server.transport {
        case .http:
            raw["type"] = "http"
            if let url = server.url {
                raw["url"] = url
            }
            if let headers = server.headers, !headers.isEmpty {
                raw["headers"] = headers
            }
        case .stdio:
            if let command = server.command {
                raw["command"] = command
            }
            if let args = server.args, !args.isEmpty {
                raw["args"] = args
            }
        }

        if let env = server.env, !env.isEmpty {
            raw["env"] = env
        }

        return raw
    }

    func readClaudeRawServers() async throws -> ServerMap {
        try await claudeConfigStore.readMCPServers().mapValues { rawServerEntry(from: $0) }
    }

    func readCodexRawServers() async throws -> ServerMap {
        try await codexConfigStore.readMCPServers().mapValues { rawServerEntry(from: $0) }
    }

    func rawServerEntry(from server: AgentCLIKit.ClaudeMCPServerConfig) -> RawServerEntry {
        var raw: RawServerEntry = [:]
        if let command = server.command {
            raw["command"] = command
        }
        if let args = server.args {
            raw["args"] = args
        }
        if let url = server.url {
            raw["url"] = url
        }
        if let headers = server.headers {
            raw["headers"] = headers
        }
        if let env = server.env {
            raw["env"] = env
        }
        if let disabled = server.disabled {
            raw["disabled"] = disabled
        }
        return raw
    }

    func rawServerEntry(from server: AgentCLIKit.CodexMCPServerConfig) -> RawServerEntry {
        var raw: RawServerEntry = [:]
        if let command = server.command {
            raw["command"] = command
        }
        if let args = server.args {
            raw["args"] = args
        }
        if let url = server.url {
            raw["url"] = url
        }
        if let headers = server.httpHeaders {
            raw["headers"] = headers
        }
        if let env = server.env {
            raw["env"] = env
        }
        if let enabled = server.enabled {
            raw["disabled"] = !enabled
        }
        return raw
    }
}
