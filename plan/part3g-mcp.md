# Part 3g: MCP

MCP service, adapters, config I/O, MCP server management. Continues from Part 3f.

## Implementation Status

- [x] `MCPServer`, `MCPConfigIO`, `MCPAdapter`, `DefaultMCPService`, the bundled recommended-server data, and `MCPViewModel` are implemented in the repo, with Claude config writes serialized through `ClaudeConfigStore` and available-agent metadata derived from `ProviderDetectionService` + `AgentRegistry`.
- [x] Focused regression coverage exists in `SkepTests/Services/MCPConfigIOTests.swift`, `SkepTests/Services/MCPAdapterTests.swift`, `SkepTests/Services/MCPServiceTests.swift`, and `SkepTests/ViewModels/MCPViewModelTests.swift`.

## MCP (Model Context Protocol)

Reference: [Claude Code MCP](https://code.claude.com/docs/en/mcp)

Selecting "MCP" in the left sidebar opens the MCP server management screen in the middle pane. This provides a unified UI for managing MCP servers across all installed agents. **MCP is not proxied through the app** -- servers are configured directly in each agent's native config format. Agents load MCP configs from their own paths at startup.

### MCP Screen UI

```
                                            ↻    🔍 Search servers...   [+ Custom MCP]
 MCP
 Connect your agents with external
 data sources and tools.

   Added
   ┌──────────────────────────────────────────────┐
   │  [X]  xcode-index-mcp            >_ stdio    │
   │       stdio server                            │
   │       🔶 🐙                                   │
   └──────────────────────────────────────────────┘

   Recommended
   ┌──────────────────────────────┐ ┌──────────────────────────────┐
   │ 🎭 Playwright    >_ stdio   │ │ 📖 Context7       @ http     │
   │    Browser automation   [+] │ │    Fetch up-to-date do. [+] │
   ├──────────────────────────────┤ ├──────────────────────────────┤
   │ 🗄️ Supabase      @ http     │ │ ▲  Vercel          @ http    │
   │    Manage databases,... [+] │ │    Analyze, debug, an. [+] │
   ├──────────────────────────────┤ ├──────────────────────────────┤
   │ 🔔 Sentry        @ http     │ │ 💳 Stripe          @ http    │
   │    Search, query, deb. [+]  │ │    Payment processi.. [+]  │
   └──────────────────────────────┘ └──────────────────────────────┘
```

**Add/Edit server form** (modal sheet):

```
┌─ Add context7 ──────────────────────── ✕ ─┐
│ Fetch up-to-date documentation and         │
│ code examples                              │
│                                            │
│ Server Name                                │
│ ┌────────────────────────────────────────┐ │
│ │ context7                               │ │
│ └────────────────────────────────────────┘ │
│                                            │
│ URL                                        │
│ ┌────────────────────────────────────────┐ │
│ │ https://mcp.context7.com/mcp           │ │
│ └────────────────────────────────────────┘ │
│                                            │
│ Environment Variables                      │
│ + Add env var                              │
│                                            │
│ Headers                                    │
│ ┌──────────────────┐ ┌──────────────┐  ✕   │
│ │ CONTEXT7_API_KEY │ │ Optional     │      │
│ └──────────────────┘ └──────────────┘      │
│ + Add header                               │
│                                            │
│ Sync to agents                             │
│ [🔶 Claude Code]                           │
│ Future agents appear here when their       │
│ shared `AgentRegistry` entry adds MCP      │
│ metadata and runtime detection support.    │
│                                    [Add]   │
└────────────────────────────────────────────┘
```

Agent chips show detected providers with their icons. In v1, only Claude appears. The chip list is derived from `MCPAgentAvailability`, not raw string IDs, so the add/edit form can render both installation state and transport support explicitly. It is built from `AgentRegistry` entries whose `mcp` section is non-nil, filtered by `ProviderDetectionService` so only installed agents appear. When future agents are added, agents that don't support the selected transport (e.g. Codex with HTTP) would be greyed out and disabled based on `supportedTransports`.

Toolbar behavior:
- **Refresh** reloads installed server config from disk and re-runs provider detection so the agent chips stay current. It does not fetch a remote catalog.
- **Search** is a local filter over the current Added + Recommended lists (name, description, and header prompts). No network request is made.

### Recommended Server List

The "Recommended" section shows a curated list of popular MCP servers. The list is **bundled as a JSON file** (`Skep/Resources/mcp-recommended.json`) compiled into the app. It contains a static array of server entries with name, description, transport type, and connection details (URL or command). The list is updated with app releases — no runtime fetch needed.

```json
[
  {
    "name": "context7",
    "description": "Fetch up-to-date documentation and code examples",
    "transport": "http",
    "url": "https://mcp.context7.com/mcp",
    "headers": ["CONTEXT7_API_KEY"]
  },
  {
    "name": "playwright",
    "description": "Browser automation for testing",
    "transport": "stdio",
    "command": "npx",
    "args": ["-y", "@anthropic/mcp-playwright"]
  }
]
```

The `headers` array lists header **names** (not values) that the user should provide — the add form prompts for these as optional fields. `MCPService.loadRecommended()` reads this file, filters out servers already installed (by name match against `loadAll()` results), and returns `RecommendedMCPServer` templates so the UI keeps the bundled description and header prompts instead of collapsing everything into a plain `MCPServer`. No network call, no caching — purely static.

### Canonical Data Model

MCP servers are stored internally as a canonical type (see `MCPServer` struct below for the Swift definition).

Bidirectional adapters transform between this canonical format and each agent's native format. The initial version supports Claude only; the shared `AgentRegistry` remains the single source of truth for which agents have MCP integration metadata, while adapter logic stays separately extensible.

| Agent | Config Path | Format | Adapter | Notes |
|---|---|---|---|---|
| Claude | `~/.claude.json` → `mcpServers` | JSON | `passthrough` | v1 — only supported agent |

Future agents would add entries here (e.g. Codex with TOML + stdio-only, Gemini with `httpUrl` field mapping, Opencode with `"remote"`/`"local"` types). Each gets an `MCPAdapterType` case and forward/reverse adapter functions — no changes to the core read/write flow.

### Adapter Format Examples (Claude)

**HTTP server** — canonical form maps directly to Claude's `mcpServers` (passthrough):
```swift
MCPServer(
    name: "context7",
    transport: .http,
    command: nil,
    args: nil,
    url: "https://mcp.context7.com/mcp",
    headers: ["X-API-KEY": "abc"],
    env: nil,
    providers: ["claude"]
)
```
```json
{
  "mcpServers": {
    "context7": {
      "url": "https://mcp.context7.com/mcp",
      "headers": { "X-API-KEY": "abc" }
    }
  }
}
```

**stdio server**:
```swift
MCPServer(
    name: "xcode-index",
    transport: .stdio,
    command: "/usr/local/bin/xcode-index-mcp",
    args: ["--project", "MyApp"],
    url: nil,
    headers: nil,
    env: ["XCODE_PATH": "/Applications/Xcode.app"],
    providers: ["claude"]
)
```
```json
{
  "mcpServers": {
    "xcode-index": {
      "command": "/usr/local/bin/xcode-index-mcp",
      "args": ["--project", "MyApp"],
      "env": { "XCODE_PATH": "/Applications/Xcode.app" }
    }
  }
}
```

Since Claude uses the canonical format directly, the `passthrough` adapter is an identity transform. Future agents that use different formats (e.g. TOML, `httpUrl` field, `type: "remote"/"local"`) would add their own adapter type with forward/reverse transform functions.

### Read/Write Flow

- **Reading**: Read each agent's config source → reverse-adapt to canonical → merge across all agents → return unified list. For Claude, the source of truth is still `~/.claude.json`, but access is funneled through `ClaudeConfigStore` so MCP and trust-entry writes share one serialized path.
- **Writing**: Take canonical server → forward-adapt per selected agent → write to each agent's config. Uses 2-phase: read all configs, then write all. Claude writes go through `ClaudeConfigStore`; other agents use direct config I/O. Editing an existing server reuses the same `addServer(_:, for:)` path as an upsert keyed by `name`.

---

### MCPServer and MCPService

```swift
struct MCPServer: Identifiable, Sendable {  // Skep/Services/MCP/MCPServer.swift
    var id: String { name }
    let name: String
    let transport: Transport
    let command: String?         // For stdio transport
    let args: [String]?          // For stdio transport
    let url: String?             // For HTTP transport
    let headers: [String: String]?
    let env: [String: String]?
    var providers: [String]      // Agent IDs this server is configured for

    enum Transport: Sendable { case stdio, http }
}

struct RecommendedMCPServer: Identifiable, Sendable {  // Skep/Services/MCP/RecommendedMCPServer.swift
    var id: String { template.id }
    let template: MCPServer
    let description: String
    let headerPrompts: [String]
}

struct MCPAgentAvailability: Identifiable, Sendable {  // Skep/Services/MCP/MCPAgentAvailability.swift
    var id: String { agentId }
    let agentId: String
    let name: String
    let supportedTransports: [MCPServer.Transport]
}

/// @MainActor because all callers are @MainActor view models and operations
/// are infrequent (user-initiated add/remove). File I/O (reading/writing
/// agent config files) is fast enough to not block the main actor.
@MainActor
protocol MCPService {  // Skep/Services/MCP/MCPService.swift
    func loadAll() async throws -> [MCPServer]
    func loadRecommended() async throws -> [RecommendedMCPServer]  // Bundled templates minus already-installed
    func addServer(_ server: MCPServer, for agents: [String]) async throws
    func removeServer(_ server: MCPServer) async throws
    func availableAgents() async -> [MCPAgentAvailability]
}
```

### Agent Config Definitions

Each agent's MCP config metadata lives on the shared `AgentRegistry` entry (`AgentDefinition.mcp`) defined in Part 2a. `DefaultMCPService` filters that registry down to MCP-capable agents, so adding a new agent does not require a second hardcoded `mcpAgentConfigs` list.

```swift
enum MCPAdapterType: String, Sendable {  // Skep/Services/MCP/MCPAdapterType.swift
    case passthrough    // Claude — canonical format as-is
    // Future: case cursor, codex, opencode, gemini, copilot
}

/// Convenience projection so MCP code can iterate only the registry entries that
/// actually support MCP.
struct MCPAgentEntry: Sendable {  // Skep/Services/MCP/MCPAgentEntry.swift
    let agentId: String
    let name: String
    let config: MCPIntegrationDefinition
}
```

### MCP Adapters

Bidirectional adapters transform between the canonical `MCPServer` format and each agent's native config. Forward adapters (canonical → agent) are used on write; reverse adapters (agent → canonical) are used on read.

```swift
/// Raw server entry as stored in agent config files (untyped dictionary).
typealias RawServerEntry = [String: Any]
/// Map of server name → raw config entry.
typealias ServerMap = [String: RawServerEntry]

enum MCPAdapter {  // Skep/Services/MCP/MCPAdapter.swift

    // MARK: - Forward (canonical → agent)

    static func adaptForward(_ type: MCPAdapterType, servers: ServerMap) -> ServerMap {
        switch type {
        case .passthrough: return servers
        // Future: case .gemini: return fwdGemini(servers)
        // Future: case .codex: return fwdCodex(servers)  // drop HTTP servers
        // etc.
        }
    }

    // MARK: - Reverse (agent → canonical)

    static func adaptReverse(_ type: MCPAdapterType, servers: ServerMap) -> ServerMap {
        switch type {
        case .passthrough: return servers
        // Future: case .gemini: return revGemini(servers)
        // etc.
        }
    }

    // Future adapter functions go here. Each agent that differs from the canonical
    // format gets a forward (canonical → agent) and reverse (agent → canonical)
    // function. Examples from emdash's proven architecture:
    //   - Gemini: url → httpUrl, inject Accept header (reverse: httpUrl → url, strip Accept)
    //   - Codex: stdio only — forward drops HTTP servers (reverse: passthrough)
    //   - Opencode: type → "remote"/"local", command as array (reverse: split back)
    //   - Copilot: inject tools: ["*"] (reverse: strip if exactly ["*"])
}
```

### Config I/O

Reading and writing agent config files. JSON only for v1 (Claude). `MCPIntegrationDefinition.format` already carries the future TOML/JSON distinction from the shared `AgentRegistry`; add TOML parsing when the first TOML-backed agent is implemented.

```swift
enum MCPConfigIO {  // Skep/Services/MCP/MCPConfigIO.swift

    /// Read the servers dictionary from an agent's config file.
    /// Returns empty dict if the file doesn't exist or is malformed.
    static func readServers(from config: MCPIntegrationDefinition) throws -> ServerMap {
        let path = (config.configPath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path),
              !data.isEmpty else { return [:] }

        guard config.format != .toml else {
            // TOML support deferred — no TOML agents in v1.
            return [:]
        }
        let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        return extractAtKeyPath(parsed, keyPath: config.serversKeyPath)
    }

    /// Write servers back to an agent's config file, preserving other keys.
    static func writeServers(to config: MCPIntegrationDefinition, servers: ServerMap) throws {
        let path = (config.configPath as NSString).expandingTildeInPath
        let dirPath = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dirPath, withIntermediateDirectories: true
        )

        // Read existing config or start from an empty root object. `setAtKeyPath`
        // below creates any missing intermediate objects, so nested key paths work
        // without a second template source of truth.
        var existing: [String: Any]
        if let data = FileManager.default.contents(atPath: path),
           !data.isEmpty {
            existing = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                ?? [:]
        } else {
            existing = [:]
        }

        // Set the servers at the key path
        setAtKeyPath(&existing, keyPath: config.serversKeyPath, value: servers)

        // Write back as JSON (TOML support deferred — no TOML agents in v1)
        let data = try JSONSerialization.data(
            withJSONObject: existing, options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    // MARK: - Key Path Helpers

    private static func extractAtKeyPath(_ dict: [String: Any], keyPath: [String]) -> ServerMap {
        var current: Any = dict
        for key in keyPath {
            guard let obj = current as? [String: Any] else { return [:] }
            current = obj[key] as Any
        }
        guard let servers = current as? [String: Any] else { return [:] }
        // Filter to only object entries (skip scalars)
        return servers.compactMapValues { $0 as? [String: Any] }
    }

    private static func setAtKeyPath(_ dict: inout [String: Any], keyPath: [String], value: Any) {
        guard !keyPath.isEmpty else { return }
        if keyPath.count == 1 {
            dict[keyPath[0]] = value
            return
        }
        var nested = dict[keyPath[0]] as? [String: Any] ?? [:]
        setAtKeyPath(&nested, keyPath: Array(keyPath[1...]), value: value)
        dict[keyPath[0]] = nested
    }

}
```

### Concrete Implementation

```swift
@MainActor
class DefaultMCPService: MCPService {  // Skep/Services/MCP/DefaultMCPService.swift
    private let claudeConfigStore: ClaudeConfigStore
    private let providerDetection: ProviderDetectionService
    private let agentRegistry: AgentRegistry
    private let bundle: Bundle

    init(
        claudeConfigStore: ClaudeConfigStore,
        providerDetection: ProviderDetectionService,
        agentRegistry: AgentRegistry,
        bundle: Bundle = .main
    ) {
        self.claudeConfigStore = claudeConfigStore
        self.providerDetection = providerDetection
        self.agentRegistry = agentRegistry
        self.bundle = bundle
    }

    private var mcpAgents: [MCPAgentEntry] {
        agentRegistry.agents.compactMap { agent in
            guard let config = agent.mcp else { return nil }
            return MCPAgentEntry(agentId: agent.id, name: agent.name, config: config)
        }
    }

    func loadAll() async throws -> [MCPServer] {
        var serversByName: [String: (server: MCPServer, providers: Set<String>)] = [:]

        // v1 merge rule: same-name servers across providers are treated as the same
        // logical server and must stay semantically identical after adapter reversal.
        // If a future provider needs divergent config for the same displayed name,
        // promote the merge key to include provider identity or surface variants in UI.

        for entry in mcpAgents {
            let rawServers: ServerMap
            do {
                rawServers = try await readRawServers(for: entry)
            } catch {
                continue  // Skip agents with unreadable configs
            }

            // Reverse-adapt from agent format to canonical
            let adapter = MCPAdapterType(rawValue: entry.config.adapterId) ?? .passthrough
            let canonical = MCPAdapter.adaptReverse(adapter, servers: rawServers)

            for (name, raw) in canonical {
                if var existing = serversByName[name] {
                    existing.providers.insert(entry.agentId)
                    serversByName[name] = existing
                } else {
                    let isHttp = raw["type"] as? String == "http"
                        || (raw["url"] != nil && raw["command"] == nil)
                    let server = MCPServer(
                        name: name,
                        transport: isHttp ? .http : .stdio,
                        command: raw["command"] as? String,
                        args: raw["args"] as? [String],
                        url: raw["url"] as? String,
                        headers: raw["headers"] as? [String: String],
                        env: raw["env"] as? [String: String],
                        providers: [entry.agentId]
                    )
                    serversByName[name] = (server, Set([entry.agentId]))
                }
            }
        }

        return serversByName.values.map { entry in
            var server = entry.server
            server.providers = Array(entry.providers)
            return server
        }
    }

    func addServer(_ server: MCPServer, for agents: [String]) async throws {
        let selectedAgents = Set(agents)
        let raw = mcpServerToRaw(server)

        // 2-phase: read all configs first, then write all
        var pendingWrites: [(entry: MCPAgentEntry, servers: ServerMap)] = []

        for entry in mcpAgents {
            var existing = (try? await readRawServers(for: entry)) ?? [:]

            if selectedAgents.contains(entry.agentId) {
                // Forward-adapt and merge
                let adapter = MCPAdapterType(rawValue: entry.config.adapterId) ?? .passthrough
                let adapted = MCPAdapter.adaptForward(adapter, servers: [server.name: raw])
                if let adaptedEntry = adapted[server.name] {
                    existing[server.name] = adaptedEntry
                }
                pendingWrites.append((entry, existing))
            } else if existing[server.name] != nil {
                // Remove from agents not in the selected set
                existing.removeValue(forKey: server.name)
                pendingWrites.append((entry, existing))
            }
        }

        for (entry, servers) in pendingWrites {
            try await writeRawServers(servers, to: entry)
        }
    }

    func removeServer(_ server: MCPServer) async throws {
        for entry in mcpAgents {
            var existing = (try? await readRawServers(for: entry)) ?? [:]
            guard existing[server.name] != nil else { continue }
            existing.removeValue(forKey: server.name)
            try await writeRawServers(existing, to: entry)
        }
    }

    func loadRecommended() async throws -> [RecommendedMCPServer] {
        guard let url = bundle.url(forResource: "mcp-recommended", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([RecommendedMCPEntry].self, from: data)
        else { return [] }

        let installed = Set((try? await loadAll())?.map(\.name) ?? [])
        return entries.compactMap { entry in
            guard !installed.contains(entry.name) else { return nil }
            return RecommendedMCPServer(
                template: MCPServer(
                    name: entry.name,
                    transport: entry.transport == "http" ? .http : .stdio,
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
    }

    private struct RecommendedMCPEntry: Decodable {
        let name: String
        let description: String
        let transport: String
        let url: String?
        let command: String?
        let args: [String]?
        let headers: [String]?  // Header names the user should provide (shown as prompts in the add form)
    }

    /// Detect which agents are installed by consulting provider detection first, not by
    /// looking for config files. An installed CLI may not have created its MCP config yet
    /// (for example, Claude before the user adds their first server). The config file is
    /// created on demand from the adapter template when the first MCP server is written.
    func availableAgents() async -> [MCPAgentAvailability] {
        var results: [MCPAgentAvailability] = []
        for entry in mcpAgents {
            let status = await providerDetection.status(for: entry.agentId)
            switch status {
            case .connected, .needsKey, .error:
                let transports: [MCPServer.Transport] = entry.config.supportsHttp ? [.stdio, .http] : [.stdio]
                results.append(MCPAgentAvailability(
                    agentId: entry.agentId,
                    name: entry.name,
                    supportedTransports: transports
                ))
            case .missing, .unchecked:
                break
            }
        }
        return results
    }

    /// Shared read path so Claude always goes through `ClaudeConfigStore`, while other
    /// providers use direct config I/O. Missing files are treated as empty config.
    private func readRawServers(for entry: MCPAgentEntry) async throws -> ServerMap {
        if entry.agentId == "claude" {
            return await claudeConfigStore.readMCPServers().mapValues { claude in
                var raw: RawServerEntry = [:]
                if let command = claude.command { raw["command"] = command }
                if let args = claude.args { raw["args"] = args }
                if let url = claude.url { raw["url"] = url }
                if let headers = claude.headers { raw["headers"] = headers }
                if let env = claude.env { raw["env"] = env }
                return raw
            }
        }
        return try MCPConfigIO.readServers(from: entry.config)
    }

    /// Shared write path so first-write creation does not depend on the config parent
    /// directory already existing. `MCPConfigIO.writeServers()` creates directories for
    /// non-Claude providers; Claude writes are serialized through `ClaudeConfigStore`.
    private func writeRawServers(_ servers: ServerMap, to entry: MCPAgentEntry) async throws {
        if entry.agentId == "claude" {
            let claudeServers = servers.mapValues { raw in
                ClaudeMCPServerConfig(
                    command: raw["command"] as? String,
                    args: raw["args"] as? [String],
                    url: raw["url"] as? String,
                    headers: raw["headers"] as? [String: String],
                    env: raw["env"] as? [String: String]
                )
            }
            await claudeConfigStore.writeMCPServers(claudeServers)
        } else {
            try MCPConfigIO.writeServers(to: entry.config, servers: servers)
        }
    }

    /// Convert canonical MCPServer to a raw dictionary for config serialization.
    private func mcpServerToRaw(_ server: MCPServer) -> RawServerEntry {
        var raw: RawServerEntry = [:]
        if server.transport == .http {
            raw["type"] = "http"
            if let url = server.url { raw["url"] = url }
            if let headers = server.headers, !headers.isEmpty { raw["headers"] = headers }
        } else {
            if let command = server.command { raw["command"] = command }
            if let args = server.args, !args.isEmpty { raw["args"] = args }
        }
        if let env = server.env, !env.isEmpty { raw["env"] = env }
        return raw
    }
}
```

**Unit tests for MCPConfigIO** (use temp files): cover read/write round-trips for all edge cases. Non-obvious:
- `readServers()` filters out non-object entries (scalars) from the servers dict
- `writeServers()` preserves existing keys in the config file (read-merge-write)
- `setAtKeyPath()` correctly sets values at multi-level key paths

**Unit tests for MCPAdapter:** cover forward/reverse identity for `.passthrough` and round-trip invertibility.

**Unit tests for MCPService** (use temp directories for agent config files, a stub `AgentRegistry`, and an injected test bundle for recommended JSON): cover all CRUD operations and detection. Non-obvious:
- `addServer()` removes the server from agents not in the selected set (deselected agents)
- `addServer()` creates the agent config file/directory on first write instead of requiring the parent path to pre-exist
- `loadAll()` deduplicates servers configured in multiple agents (merges provider lists)
- `loadRecommended()` excludes servers that are already installed (by name match)
- `loadRecommended()` preserves bundled descriptions and header prompts on `RecommendedMCPServer`
- Claude MCP reads/writes are serialized through `ClaudeConfigStore`, so adding trust entries and MCP servers cannot clobber each other in `~/.claude.json`
- MCP-capable agents are derived from `AgentRegistry.mcp`; adding a new MCP-aware agent requires one shared registry entry plus adapter support, not a second `mcpAgentConfigs` edit
- `availableAgents()` is driven by `ProviderDetectionService` rather than config-file existence, so installed CLIs appear even before their first MCP config write
- `availableAgents()` surfaces `supportedTransports`, so the add/edit form can disable incompatible provider chips without hardcoded per-screen logic

### MCPViewModel

```swift
@MainActor @Observable
class MCPViewModel {  // Skep/ViewModels/MCPViewModel.swift
    private let mcpService: MCPService
    private(set) var servers: [MCPServer] = []
    private(set) var recommended: [RecommendedMCPServer] = []
    private(set) var availableAgents: [MCPAgentAvailability] = []
    var searchQuery: String = ""

    var filteredServers: [MCPServer] { ... }
    var filteredRecommended: [RecommendedMCPServer] { ... }

    func load() async { ... }          // Populates servers, recommended, and availableAgents
    func addServer(_ server: MCPServer, for agents: [String]) async throws { ... }
    func removeServer(_ server: MCPServer) async throws { ... }
    func refreshProviders() async { ... }
}
```

`filteredServers` and `filteredRecommended` perform a case-insensitive local match against server name, recommended description, and header prompt names. `MCPScreen` binds its search field directly to `searchQuery` and renders the filtered collections; the underlying `servers` / `recommended` arrays remain the source of truth populated by `load()`.

**Used by**: `MCPScreen` (middle pane when "MCP" selected in sidebar).

Minimal screen signature:

```swift
struct MCPScreen: View {  // Skep/Views/MCP/MCPScreen.swift
    let viewModel: MCPViewModel
}
```

`MCPScreen` owns the initial `.task` that calls `await viewModel.load()` on first appearance. `MiddlePane` only creates/caches the VM.

**Unit tests for MCPViewModel** (inject `MockMCPService`): cover load/add/remove delegation and state refresh. Non-obvious:
- `addServer()` moves the server from recommended to servers after refresh
- `removeServer()` moves the server back to recommended after refresh
- `searchQuery` filters both Added and Recommended lists locally without invoking extra service calls
- `load()` surfaces `availableAgents` with transport support, so the add form can disable incompatible provider chips without extra registry lookups in the view

**Snapshot tests for MCPScreen:** cover server list, the no-added intro-card state with recommended servers still visible, the true full-screen empty fallback (`servers` + `recommended` both empty), and add server form.
