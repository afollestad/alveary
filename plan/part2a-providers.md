# Part 2a: Providers

Provider adapters, registry, detection, environment, turn state/message queue, activity classification. Depends on Part 1.

`ConversationEvent`, `AgentConfig`, `AgentSpawnConfig`, and `AgentError` are defined in `Skep/Services/Agent/ConversationEvent.swift`, `Skep/Services/Agent/AgentConfig.swift`, and `Skep/Services/Agent/AgentError.swift` (Part 1). All adapter and agent code in this Part builds on those types.

**Build order**: follow the **Phase 3 table** in `PLAN.md`. Part 2's file order is **not** the source of truth for implementation order anymore. Two important exceptions are built earlier than their file position suggests: `SessionManager` comes from [Part 2i](part2i-session.md) at Phase 3 step #7, and `SetupPhase` comes from the [ConversationViewModel Behaviors supplement](supplement-conversation-viewmodel-behaviors.md) at step #9 before `ConversationViewModel` itself exists. `ClaudeAdapter` is still defined after `AgentsManager` (in "Turn State and Event Lifecycle") — stub `resolveAdapter()` with `fatalError("TODO")` when building `AgentsManager` (#9), then implement the adapter at #10.

**Scope note for v1**: the architecture is intentionally **Claude-first** and only fully specifies **long-lived bidirectional providers**. Single-turn providers remain a future extension point, but the replacement-process ownership is already defined: adapters do **not** spawn new processes inside `sendMessage()`. When a provider needs a fresh process for the next turn, `AgentsManager` re-spawns it from the last successful `AgentSpawnConfig` and passes the turn via `initialPrompt`, so process tracking stays centralized. For bidirectional providers, that prompt is delivered immediately after spawn with the same stdin write path as `sendMessage()`; for future single-turn providers, the adapter can encode `initialPrompt` into its CLI args.

## Provider Adapters

Each provider has an adapter (protocol conformance) that abstracts how the CLI is spawned, how messages are sent, how output is decoded, and whether the process is long-lived or single-turn. In v1, adapters are intentionally **immutable/stateless**. If a future provider needs decode-time mutable state, keep that state in a per-process helper owned by the stdout reader task rather than on the shared adapter instance.

```swift
enum SessionContinuity: Sendable {
    case preserved
    case restartedFresh
}

struct SessionLaunchDecision: Sendable {
    let args: [String]
    let continuity: SessionContinuity
}

protocol AgentAdapter: Sendable {  // Skep/Services/Agent/AgentAdapter.swift
    /// Build CLI arguments for spawning the process.
    func buildArgs(config: AgentConfig) -> [String]

    /// Additional env vars for this provider.
    func envOverrides(config: AgentConfig) -> [String: String]

    /// Decode a JSON line from stdout into universal events.
    func decode(_ json: [String: Any]) -> [ConversationEvent]

    /// Called after the stdout stream ends (process exited or pipe closed).
    /// Returns any final events that should be yielded before the stream finishes.
    /// Use this to flush accumulated partial state (e.g. an incomplete message
    /// chunk sequence). For Claude, returns [] since all events are complete
    /// JSON lines. Future adapters that accumulate multi-line output may need
    /// to flush here.
    func finalize() -> [ConversationEvent]

    /// Send a user message to an already-running process. For v1 bidirectional
    /// providers, this writes to stdin. Providers that need a fresh process per
    /// turn do not spawn from here — `AgentsManager` re-spawns them from the
    /// stored `AgentSpawnConfig` and passes the message as `initialPrompt`.
    func sendMessage(_ message: String, to process: Process) throws

    /// Returns the provider-owned session artifact path when one exists.
    /// E.g. Claude stores sessions at ~/.claude/projects/<encoded-cwd>/<uuid>.jsonl.
    /// Providers that resume through some non-file mechanism can return nil.
    func sessionFilePath(sessionId: String, cwd: String) -> String?

    /// Whether this provider can currently resume the persisted session binding.
    /// Claude implements this as an on-disk jsonl existence check; future providers
    /// may inspect repo-local metadata, SQLite, or another provider-owned store.
    func canResumeSession(sessionId: String, cwd: String) -> Bool

    /// Build provider-specific session args from the persisted session binding.
    /// This keeps `--resume` / `--session-id` ownership out of `SessionManager`,
    /// which only stores app-side conversation ↔ session identity. The returned
    /// continuity flag lets higher layers surface when a missing provider artifact
    /// forced a fresh-session fallback under otherwise preserved local app history.
    func sessionLaunch(sessionId: String, cwd: String, isResuming: Bool, forkSession: Bool) -> SessionLaunchDecision

    /// Whether the process stays alive across turns.
    var supportsBidirectionalStreaming: Bool { get }

    /// Whether writing to stdin mid-turn reaches the agent immediately.
    /// Future-facing capability metadata; v1 chat steering is only wired for Claude,
    /// so non-steering providers must not yet expose Shift+Enter steering until the
    /// plan defines a concrete interrupt-and-next-turn fallback owner.
    var supportsMidTurnSteering: Bool { get }
}
```

**Claude adapter** -- long-lived process, bidirectional streaming. Decodes Messages API-style events with `type: "system"/"assistant"/"user"/"result"`. Sends messages by writing JSON to stdin. Supports mid-turn steering.

**Future adapters** for single-turn providers (e.g. Codex `exec --json`) should keep process replacement in `AgentsManager`, not inside the adapter. The adapter still owns CLI args, provider-specific session resume checks/flags, and decoding; the manager owns re-spawn, stream task registration, and lifecycle tracking so replacement turns remain visible to shutdown, status, and buffering logic.

Adding a new bidirectional provider means adding provider metadata, an adapter, and any provider-specific session/setup strategy. The chat rendering layer stays generic, but the process/session layer is not yet registry-only.

---

## Provider Registry

The app should be architected around a **single source of truth for agent metadata**. A shared `AgentRegistry` owns install/docs metadata plus optional feature-specific sections (provider runtime, skills sync path, MCP config path). `ProviderRegistry` is then a **projection** over that shared registry for agent entries that can be spawned by the chat/runtime layer.

For the Claude-first v1 runtime, treat the registry as the source of truth for **install guidance, detection commands, and capability metadata**. The validated Claude spawn flags themselves still live in `ClaudeAdapter.buildArgs()` / `sessionLaunch()` rather than being assembled generically from registry fields.

Adding a new agent provider still requires a registry entry **plus** an adapter and any provider-specific session/setup strategy. Registry metadata drives CLI discovery, capability flags, and user-facing install/setup guidance, but it is not the sole integration point.

Services that vary by provider (session storage strategy, hook delivery mechanism, resume arg building) should be defined as protocols and resolved via Knit's compile-time dependency injection. This keeps provider-specific logic isolated in dedicated modules that can be swapped or extended without touching shared infrastructure.

### Swift Registry Definition

```swift
struct PermissionModeOption: Sendable {  // Skep/Services/Detection/ProviderDefinition.swift
    let value: String        // e.g. "default", "plan", "acceptEdits"
    let label: String        // UI label, e.g. "Default", "Plan", "Auto-Edit"
    let description: String  // Short user-facing explanation shown in menus/tooltips
}

struct ProviderDefinition: Sendable {  // Skep/Services/Detection/ProviderDefinition.swift
    let id: String
    let name: String
    let cli: String                    // Default CLI command name
    let commands: [String]             // Alternative command names to try
    let versionArgs: [String]          // Args for version check (e.g. ["--version"])

    // CLI flags / metadata
    let autoApproveFlag: String?       // Legacy metadata for UI/docs; v1 Claude uses permissionModeFlag instead
    let initialPromptFlag: String?     // Reserved for future single-turn providers; Claude sends first prompt via stdin
    let resumeFlag: String?            // Reserved metadata for provider-specific resume commands (e.g. "--resume")
    let sessionIdFlag: String?         // e.g. "--session-id" (nil if unsupported)
    let planActivateCommand: String?   // e.g. "/plan" (nil if unsupported)

    // Structured output and multi-turn
    let structuredOutputArgs: [String]? // e.g. ["-p", "--output-format", "stream-json"]
    let structuredInputArgs: [String]?  // e.g. ["--input-format", "stream-json"] (nil if single-turn)
    let execSubcommand: String?         // e.g. "exec" for Codex (nil if CLI takes prompt directly)
    let supportsBidirectionalStreaming: Bool // true if multi-turn via stdin JSON
    let supportsMidTurnSteering: Bool   // Can the CLI read stdin during processing?
    let permissionModeFlag: String?     // e.g. "--permission-mode" (nil if unsupported)
    let supportedPermissionModes: [PermissionModeOption]? // nil hides the dropdown/CTA entirely
    let suggestedWriteEscalationMode: String? // e.g. "acceptEdits" for a permission-denial CTA; nil = dismiss-only banner
    let writeEscalationEligibleTools: Set<String> // Denied tool names that the suggested write escalation can actually unblock
    let effortFlag: String?             // e.g. "--effort" (nil if unsupported)
    let supportedEffortLevels: [String]? // e.g. ["low", "medium", "high", "max"] (nil if unsupported)
}

struct MCPIntegrationDefinition: Sendable {  // Skep/Services/Detection/AgentDefinition.swift
    let configPath: String
    let serversKeyPath: [String]
    let format: ConfigFormat
    let adapterId: String
    let supportsHttp: Bool

    enum ConfigFormat: Sendable { case json, toml }
}

struct AgentDefinition: Sendable {  // Skep/Services/Detection/AgentDefinition.swift
    let id: String
    let name: String
    let installCommand: String?
    let docUrl: String?
    let provider: ProviderDefinition?
    let skillsDirectory: String?
    let mcp: MCPIntegrationDefinition?
}

protocol AgentRegistry {  // Skep/Services/Detection/AgentRegistry.swift
    var agents: [AgentDefinition] { get }
    func agent(for id: String) -> AgentDefinition?
}

protocol ProviderRegistry {  // Skep/Services/Detection/ProviderRegistry.swift
    var providers: [ProviderDefinition] { get }
    func provider(for id: String) -> ProviderDefinition?
}

final class DefaultAgentRegistry: AgentRegistry {  // Skep/Services/Detection/DefaultAgentRegistry.swift
    let agents: [AgentDefinition] = [
        AgentDefinition(
            id: "claude",
            name: "Claude Code",
            installCommand: "curl -fsSL https://claude.ai/install.sh | bash",
            docUrl: "https://code.claude.com/docs/en/quickstart",
            provider: ProviderDefinition(
                id: "claude",
                name: "Claude Code",
                cli: "claude",
                commands: ["claude"],
                versionArgs: ["--version"],
                autoApproveFlag: "--dangerously-skip-permissions",  // Legacy metadata; prefer --permission-mode bypassPermissions
                initialPromptFlag: nil,
                resumeFlag: "--resume",
                sessionIdFlag: "--session-id",
                planActivateCommand: "/plan",
                structuredOutputArgs: ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages"],
                structuredInputArgs: ["--input-format", "stream-json"],
                execSubcommand: nil,
                supportsBidirectionalStreaming: true,
                supportsMidTurnSteering: true,
                permissionModeFlag: "--permission-mode",
                supportedPermissionModes: [
                    PermissionModeOption(value: "default", label: "Default", description: "Safe default; denied writes come back as tool errors in non-interactive mode."),
                    PermissionModeOption(value: "plan", label: "Plan", description: "Read-only exploration and planning."),
                    PermissionModeOption(value: "acceptEdits", label: "Auto-Edit", description: "Auto-accept file edits while keeping stronger checks for other actions."),
                    PermissionModeOption(value: "auto", label: "Auto", description: "Auto-approve most actions with safety checks."),
                    PermissionModeOption(value: "bypassPermissions", label: "Auto-Approve", description: "Bypass permission checks entirely.")
                ],
                suggestedWriteEscalationMode: "acceptEdits",
                writeEscalationEligibleTools: ["Write", "Edit", "MultiEdit"],
                effortFlag: "--effort",
                supportedEffortLevels: ["low", "medium", "high", "max"]
            ),
            skillsDirectory: "~/.claude/skills",
            mcp: MCPIntegrationDefinition(
                configPath: "~/.claude.json",
                serversKeyPath: ["mcpServers"],
                format: .json,
                adapterId: "passthrough",
                supportsHttp: true
            )
        ),
        // Future: add Codex, Amp, Goose, etc. here. Agents that only participate
        // in skills sync can set `provider: nil` while still supplying a
        // `skillsDirectory` and/or `mcp` section.
    ]

    func agent(for id: String) -> AgentDefinition? {
        agents.first { $0.id == id }
    }
}

final class DefaultProviderRegistry: ProviderRegistry {  // Skep/Services/Detection/DefaultProviderRegistry.swift
    private let agentRegistry: AgentRegistry

    init(agentRegistry: AgentRegistry) {
        self.agentRegistry = agentRegistry
    }

    var providers: [ProviderDefinition] {
        agentRegistry.agents.compactMap(\.provider)
    }

    func provider(for id: String) -> ProviderDefinition? {
        agentRegistry.agent(for: id)?.provider
    }
}
```

The same shared registry later feeds install guidance, Skills sync/discovery paths, and MCP config metadata, so those features do not need their own hardcoded agent lists or duplicated per-agent strings.

Claude's registry entry (the only provider in the initial version):

| Field | Value |
|---|---|
| `cli` | `claude` |
| `autoApproveFlag` | `--dangerously-skip-permissions` (legacy metadata; prefer `--permission-mode bypassPermissions`) |
| `resumeFlag` | `--resume` |
| `sessionIdFlag` | `--session-id` |
| `structuredOutputArgs` | `["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages"]` |
| `structuredInputArgs` | `["--input-format", "stream-json"]` |
| `supportsBidirectionalStreaming` | `true` |
| `supportsMidTurnSteering` | `true` |
| `permissionModeFlag` | `--permission-mode` |
| `supportedPermissionModes` | `default`, `plan`, `acceptEdits`, `auto`, `bypassPermissions` |
| `suggestedWriteEscalationMode` | `acceptEdits` |
| `writeEscalationEligibleTools` | `Write`, `Edit`, `MultiEdit` |
| `effortFlag` | `--effort` |
| `supportedEffortLevels` | `["low", "medium", "high", "max"]` |

Future providers would add their own entries with different values. The adapter pattern handles the differences.

### CLI Argument Building

In v1, CLI argument assembly is split across three layers:

1. **Adapter args** — provider-specific structured-output, permission, model, and effort flags from `AgentAdapter.buildArgs()`. For Claude these are hardcoded validated flags, not a generic registry-driven assembler yet.
2. **Session args** — `SessionManager` reconciles/persists the conversation's session identity, then the adapter turns that binding into provider-specific launch args plus continuity metadata via `sessionLaunch(...)`.
3. **User overrides** — custom CLI path, extra args, and env from `ProviderCustomConfig`. In the Claude-first v1 runtime, these are the only custom config fields that actively affect spawning; `resumeFlag`, `defaultArgs`, `autoApproveFlag`, and `initialPromptFlag` remain reserved metadata for future providers.

For Claude, the initial user prompt is **not** appended as a trailing CLI arg. The process is spawned first, then `AgentsManager.spawn()` sends the prompt via stdin JSON if `initialPrompt` is non-empty.

### Provider CLI Detection

The provider detection service checks installed agent CLIs by running version checks (e.g. `claude --version`). It tries multiple commands per provider (e.g. `claude` vs a custom alias), caches the resolved path and install status. The cached path is what the process spawner uses to find the executable.

---

## Provider Detection and Installation

Before spawning an agent, the app must verify the CLI is installed and find its executable path.

### Detection Flow

On app startup and on manual refresh, each provider's CLI is checked:

1. If the user configured a custom CLI override for this provider, try that exact path/command first; otherwise fall back to the provider's `commands` array (for example `["claude"]`). A custom override may be either an explicit path or a command name. Command names must still go through the same `which`-style resolution path as registry commands; only explicit paths skip resolution.
2. Run `<command> --version` with a 3-second timeout.
3. Resolve the executable path (for direct spawn).
4. Classify status: `unchecked` (not probed yet this launch), `connected` (found and working), `missing` (checked and not installed), `needs_key` (installed but auth missing), `error` (found but broken). The `needs_key` classification is a Claude-first stderr heuristic in v1, not a generic provider contract yet.

Results are cached in memory for the current launch. v1 does not persist a provider-status disk cache because CLI checks are cheap and the runtime still re-validates on demand before spawn.

If a check times out but the binary was found, a retry is scheduled (1.5s delay, doubled timeout up to 12s). This handles slow first-run scenarios where the CLI may be initializing.

```swift
enum ProviderStatus: Sendable {  // Skep/Services/Detection/ProviderDetectionService.swift
    case unchecked
    case connected(path: String, version: String)
    case missing
    case needsKey
    case error(String)
}

protocol ProviderDetectionService: Actor {  // Skep/Services/Detection/ProviderDetectionService.swift
    func resolvedPath(for providerId: String) -> String?
    func status(for providerId: String) -> ProviderStatus
    func checkAllProviders() async
    func checkProvider(_ providerId: String) async
}
```

The concrete `DefaultProviderDetectionService` uses `ShellRunner` to execute version checks. Results are cached in memory for the current launch. `AgentsManager` reads `resolvedPath(for:)` at spawn time, but if the path is still unknown it performs an on-demand `checkProvider()` before surfacing `cliNotInstalled` so startup timing does not create false negatives.

### Re-Detection Triggers

The initial check runs at app startup, but CLI availability can change during the app's lifetime (user installs/updates a CLI, system wakes from sleep with changed PATH, etc.). Detection is re-run in these cases:

1. **System wake** -- subscribe to `NSWorkspace.didWakeNotification`. On wake, schedule `checkAllProviders()` with a short delay (~2s) to let the system stabilize.
2. **Spawn failure** -- if `AgentsManager.spawn()` throws because `process.run()` fails (e.g. "No such file or directory"), re-run `checkProvider()` so the command is re-resolved and the cached path/status are overwritten with fresh detection results. The refreshed status/path is then available for the next user action; v1 does not auto-retry the same spawn attempt.
3. **Manual refresh** -- the "Refresh" button in the empty state / provider detection UI calls `checkAllProviders()`.
4. **Custom CLI override changed** -- when the user edits `ProviderCustomConfig.cli`, re-run `checkProvider(providerId)` so sidebar/settings install state and the cached resolved path stay in sync with the new override.

No periodic polling is needed — the above triggers cover the realistic scenarios.

### Concrete Implementation

```swift
/// Actor to prevent data races on `statuses` and `resolvedPaths`, which are
/// written by concurrent tasks in `checkAllProviders()`.
actor DefaultProviderDetectionService: ProviderDetectionService {  // Skep/Services/Detection/DefaultProviderDetectionService.swift
    private let shell: ShellRunner
    private let registry: ProviderRegistry
    private let settingsService: SettingsService
    private var statuses: [String: ProviderStatus] = [:]
    private var resolvedPaths: [String: String] = [:]

    init(shell: ShellRunner, registry: ProviderRegistry, settingsService: SettingsService) {
        self.shell = shell
        self.registry = registry
        self.settingsService = settingsService
    }

    func resolvedPath(for providerId: String) -> String? { resolvedPaths[providerId] }
    func status(for providerId: String) -> ProviderStatus { statuses[providerId] ?? .unchecked }

    /// Note: `checkProvider()` is actor-isolated, so child tasks in the group
    /// serialize on this actor's executor — they do NOT run concurrently despite
    /// `withTaskGroup`. With v1's single provider this is irrelevant. When adding
    /// multiple providers, extract the shell/network calls into a `nonisolated`
    /// helper that returns a result, then apply the result to actor state.
    func checkAllProviders() async {
        await withTaskGroup(of: Void.self) { group in
            for provider in registry.providers {
                group.addTask { await self.checkProvider(provider.id) }
            }
        }
    }

    func checkProvider(_ providerId: String) async {
        guard let provider = registry.provider(for: providerId) else { return }
        await checkProvider(provider, timeout: .seconds(3), attempt: 1)
    }

    private func checkProvider(_ provider: ProviderDefinition, timeout: Duration, attempt: Int) async {
        let customCli = await settingsService.current.providerConfigs[provider.id]?.cli?.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateCommands = ([customCli].compactMap { cli -> String? in
            guard let cli, !cli.isEmpty else { return nil }
            return cli
        } + provider.commands)

        for command in candidateCommands {
            let path: String
            if command.contains("/") {
                path = command
            } else {
                // Resolve named commands via `which`; explicit custom paths skip this step.
                let whichResult = try? await shell.run(
                    executable: "/usr/bin/which", args: [command], timeout: .seconds(2)
                )
                guard let resolvedPath = whichResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                      whichResult?.succeeded == true, !resolvedPath.isEmpty else { continue }
                path = resolvedPath
            }

            // 2. Run the version check
            do {
                let result = try await shell.run(
                    executable: path, args: provider.versionArgs, timeout: timeout
                )
                if result.succeeded {
                    let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    statuses[provider.id] = .connected(path: path, version: version)
                    resolvedPaths[provider.id] = path
                    return
                }
                // Non-zero exit — CLI is broken or needs auth
                if result.stderr.contains("API key") || result.stderr.contains("not authenticated") {
                    statuses[provider.id] = .needsKey
                } else {
                    statuses[provider.id] = .error(result.stderr)
                }
                resolvedPaths[provider.id] = path
                return
            } catch is ShellError {
                // Timeout — binary exists but is slow (first-run init). Retry with doubled timeout.
                if attempt < 3 {
                    let nextTimeout = Duration.seconds(timeout.components.seconds * 2)
                    // Brief delay before retry to let the CLI finish initializing.
                    try? await Task.sleep(for: .seconds(1.5))
                    await checkProvider(provider, timeout: nextTimeout, attempt: attempt + 1)
                    return
                }
                statuses[provider.id] = .error("Version check timed out after \(attempt) attempts")
                resolvedPaths[provider.id] = path
                return
            } catch {
                statuses[provider.id] = .error(error.localizedDescription)
                return
            }
        }
        // None of the commands were found
        statuses[provider.id] = .missing
        resolvedPaths.removeValue(forKey: provider.id)
    }
}
```

**Unit tests for ProviderDetectionService** (inject `MockShellRunner`): cover all `ProviderStatus` cases (`.unchecked`, `.connected`, `.missing`, `.needsKey`, `.error`). Non-obvious:
- Unchecked providers stay `.unchecked` until a real probe runs; install guidance must not treat the launch-default state as authoritative
- Custom CLI override is checked before registry commands, named custom commands still resolve through `which`, and explicit custom paths skip the `which` hop
- Retries with doubled timeout on first timeout, up to 3 attempts before returning `.error`
- `resolvedPath()` returns nil for unchecked providers (not just missing ones), and the spawn path performs an on-demand `checkProvider()` before failing

**Unit tests for AgentRegistry / ProviderRegistry:** cover `agent(for:)` and `provider(for:)` lookup, verify Claude's install/docs metadata lives only on the shared agent entry, verify the provider projection still exposes the expected runtime fields, and verify the Claude registry capability flags stay in sync with `ClaudeAdapter`'s declared capabilities.

**Unit tests for AgentEnvironmentBuilder**: cover base vars, auth var forwarding (set vs unset), and provider-specific overrides.

### Installation Guidance

For missing providers, show the `installCommand` from the shared `AgentRegistry` entry matching that provider ID (e.g. `npm install -g @openai/codex`, `curl -fsSL https://claude.ai/install.sh | bash`). For `gh` CLI: `brew install gh`.

### Custom Provider Configuration

Users can override provider CLI settings via `ProviderCustomConfig` (in `Skep/Services/Settings/AppSettings.swift`). The `providerConfigs` dictionary on `AppSettings` maps provider IDs to custom configs. In the Claude-first v1 runtime, `cli`, `extraArgs`, and `env` are the active override points; the other fields remain reserved metadata for future provider-specific launchers. Empty-string values should be normalized away at settings-write time rather than treated as meaningful CLI tokens.

---

## Environment Variables

### Passed to All Agents

- `TERM=xterm-256color`, `COLORTERM=truecolor`, `TERM_PROGRAM=Skep` (set for compatibility even though structured JSON output doesn't use ANSI codes)
- `HOME`, `USER`, `PATH`
- `LANG` (defaults to `en_US.UTF-8` if the parent environment does not provide one)
- `TMPDIR`, `SSH_AUTH_SOCK` (if set)

### Agent Auth Vars (`AGENT_ENV_VARS`)

A curated allowlist of ~40+ environment variables passed through from the parent process environment. Includes `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, various AWS/Azure/Google credentials, proxy settings, and provider-specific keys. Only variables that are actually set in the parent environment are forwarded.

### Swift Example: Building the Agent Process Environment

```swift
protocol AgentEnvironmentBuilder: Sendable {  // Skep/Services/Agent/AgentEnvironmentBuilder.swift
    func buildEnvironment(providerEnv: [String: String]?) -> [String: String]
}

final class DefaultAgentEnvironmentBuilder: AgentEnvironmentBuilder, @unchecked Sendable {  // Skep/Services/Agent/DefaultAgentEnvironmentBuilder.swift
    func buildEnvironment(providerEnv: [String: String]? = nil) -> [String: String] {
        let env = ProcessInfo.processInfo.environment
        var result: [String: String] = [
            "TERM": "xterm-256color",
            "COLORTERM": "truecolor",
            "TERM_PROGRAM": "Skep",
            "HOME": env["HOME"] ?? NSHomeDirectory(),
            "USER": env["USER"] ?? NSUserName(),
            "PATH": env["PATH"] ?? "/usr/local/bin:/usr/bin:/bin",
            "LANG": env["LANG"] ?? "en_US.UTF-8",
        ]

        // Pass through optional system vars
        for key in ["TMPDIR", "SSH_AUTH_SOCK"] {
            if let value = env[key] { result[key] = value }
        }

        // Pass through agent auth vars from allowlist
        for key in agentEnvVars {
            if let value = env[key] { result[key] = value }
        }

        // Provider-specific env overrides
        if let providerEnv {
            for (key, value) in providerEnv { result[key] = value }
        }

        return result
    }

    /// Allowlist of environment variables to pass through for agent authentication.
    private let agentEnvVars = [
        "ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY",
        "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN",
        "AWS_REGION", "AWS_PROFILE",
        "GITHUB_TOKEN", "GH_TOKEN",
        "HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY",
        // ... ~40 more
    ]
}
```

---

## Claude Shared Config Store

Claude-specific features in different subsystems all touch the same files: `~/.claude.json` (global trust + MCP config) and `<cwd>/.claude/settings.local.json` (project-local settings). Those writes must be serialized through one shared service so MCP edits and auto-trust writes cannot clobber each other with competing read-merge-write cycles.

```swift
struct ClaudeMCPServerConfig: Codable, Sendable {  // Skep/Services/Agent/ClaudeConfigStore.swift
    var command: String?
    var args: [String]?
    var url: String?
    var headers: [String: String]?
    var env: [String: String]?
}

protocol ClaudeConfigStore: Actor {  // Skep/Services/Agent/ClaudeConfigStore.swift
    func ensureLocalSettingsFile(in workingDirectory: String) async
    func upsertTrustedProject(path: String) async
    func readMCPServers() async -> [String: ClaudeMCPServerConfig]
    func writeMCPServers(_ servers: [String: ClaudeMCPServerConfig]) async
}

actor DefaultClaudeConfigStore: ClaudeConfigStore {  // Skep/Services/Agent/DefaultClaudeConfigStore.swift
    // Owns all read/merge/write access to ~/.claude.json and per-project local settings.
    // Uses atomic temp-file replacement for global writes and never overwrites an existing
    // settings.local.json. MCPService and ProviderSetupService both go through this actor.
}
```

This is intentionally Claude-specific in v1. Future providers can add their own config store if they need coordinated writes to provider-owned files.

**Unit tests for ClaudeConfigStore** (use temp directories/files): cover local settings creation, trust entry merge, MCP server round-trips, and first-run file creation. Non-obvious:
- Trust-entry and MCP writes preserve each other's keys inside `~/.claude.json` (no lost-update clobbering)
- `ensureLocalSettingsFile(in:)` creates `{}` only when missing and never overwrites existing content

---

## Provider Setup Service

Provider-specific pre-spawn setup (config files, trust entries, etc.) extracted into a service so each provider can define its own setup requirements. The single owner is `ConversationViewModel.prepareForSpawn()` / `startAgentReserved()` on every user-visible spawn path (`startAgent`, respawn, and reconfigure) before `AgentsManager.spawn()` is called. No other layer should bypass that preflight by calling `AgentsManager.spawn()` directly from unrelated UI code.

```swift
protocol ProviderSetupService: Actor {  // Skep/Services/Agent/ProviderSetupService.swift
    /// Perform provider-specific setup before spawning an agent process.
    /// Best-effort and intentionally non-fatal in v1. Implementations should serialize
    /// shared-file writes so concurrent thread creation cannot clobber config.
    /// `autoTrust` is only enabled by callers for real worktree launches; project-root
    /// threads intentionally skip trust writes even when the user enabled
    /// "Auto-trust worktrees" in settings.
    func prepareForSpawn(providerId: String, workingDirectory: String, autoTrust: Bool) async
}

actor DefaultProviderSetupService: ProviderSetupService {  // Skep/Services/Agent/DefaultProviderSetupService.swift
    private let claudeConfigStore: ClaudeConfigStore

    init(claudeConfigStore: ClaudeConfigStore) {
        self.claudeConfigStore = claudeConfigStore
    }

    func prepareForSpawn(providerId: String, workingDirectory: String, autoTrust: Bool) async {
        switch providerId {
        case "claude":
            await claudeConfigStore.ensureLocalSettingsFile(in: workingDirectory)
            if autoTrust {
                await claudeConfigStore.upsertTrustedProject(path: workingDirectory)
            }
        default:
            break  // Future providers add their setup here
        }
    }
}
```

**Unit tests for ProviderSetupService** (use temp directories): cover Claude setup (`settings.local.json` + trust entry), non-Claude provider (no-op), and auto-trust disabled (skips trust entry). Non-obvious:
- Trust entry key is the literal absolute path (not slashes-to-dashes encoding)
- Empty string values in the local settings file still produce a valid `{}` JSON file
- First-run trust write succeeds when `~/.claude.json` does not exist yet (move, not replace)
- Existing `.claude/settings.local.json` content is left untouched; `~/.claude.json` uses read-merge-write so unrelated keys survive
- Concurrent `prepareForSpawn()` calls serialize writes to shared `~/.claude.json` and preserve both trust entries (no last-writer-wins clobbering)

---

## Turn State and Message Queue

Simple types used by `ConversationState`. Defined here so they exist before the `AgentsManager` code block.

```swift
@MainActor @Observable
class TurnState {  // Skep/Utilities/TurnState.swift
    private(set) var isActive: Bool = false

    func beginTurn() {
        isActive = true
    }

    func endTurn() {
        isActive = false
    }
}
```

The UI reads `turnState.isActive` to determine:
- Whether to show the live progress area and busy-state input affordances
- Whether the Send button should be a Stop button
- Whether new messages should be queued

```swift
/// Wrapper for queued messages with stable identity for SwiftUI `ForEach`.
/// Using array indices as view IDs causes wrong-element removal animations
/// when items are deleted from the middle of the queue — SwiftUI can't
/// distinguish "item removed" from "item shifted" when IDs change on every
/// mutation. A stable UUID per entry avoids this.
struct QueuedMessage: Identifiable, Sendable {  // Skep/Utilities/MessageQueue.swift
    let id = UUID()
    let text: String
    /// Snapshot of the staged context that was attached when the user queued this
    /// message. Preserves "next message" semantics even if the input banner is later
    /// dismissed or replaced before the queue drains.
    let stagedContext: String?
}

@MainActor @Observable
class MessageQueue {  // Skep/Utilities/MessageQueue.swift
    private(set) var pending: [QueuedMessage] = []

    func enqueue(_ message: String, stagedContext: String? = nil) {
        pending.append(QueuedMessage(text: message, stagedContext: stagedContext))
    }

    func peekNext() -> QueuedMessage? {
        pending.first
    }

    func dequeueNext() -> QueuedMessage? {
        pending.isEmpty ? nil : pending.removeFirst()
    }

    @discardableResult
    func remove(id: UUID) -> QueuedMessage? {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return nil }
        return pending.remove(at: index)
    }

    func clear() { pending.removeAll() }
}
```

Both are `@MainActor` because all consumers (`ConversationViewModel`, `ChatView`) run on the main actor. Both are owned by `ConversationState` (see next section).

**Unit tests for TurnState:** cover `beginTurn()`, `endTurn()`, and initial state.

`turnState.isActive` does **not** hide the chat composer in v1. The input stays visible and editable while busy so the user can queue the next message or use Claude steering; the flag only switches the composer into its busy controls/state and drives the live working area.

**Unit tests for MessageQueue:** cover enqueue/dequeue ordering, `remove(id:)`, and `clear()`. Non-obvious:
- Each enqueued message has a unique stable `id` (UUID-based, not array index — important for SwiftUI identity)
- `stagedContext` snapshots survive enqueue/dequeue unchanged so queued messages keep the context they were created with
- `peekNext()` is non-mutating so queued auto-send can inspect the head without dropping it on failure
- `remove(id:)` returns the removed entry when present so the VM can restore staged-context ownership if the user dismisses the queued message that claimed it
- `remove(id:)` is a no-op for unknown UUIDs (returns `nil`, no crash)

---

## Activity Classification (Agent Status)

```swift
enum ActivitySignal: Sendable {  // Skep/Services/Agent/ActivitySignal.swift
    case neutral    // No live status entry yet (never spawned, or post-relaunch/restore before respawn)
    case busy       // Agent is processing (receiving events)
    case idle       // Agent turn completed, waiting for input
    case stopped    // Process exited
    case error      // Error event received or non-zero exit
}
```

With structured JSON output, agent status is derived directly from the event stream — no regex heuristics needed. See **Agent Lifecycle Detection** in [Part 2g](part2g-status-and-lifecycle.md) for the full signal table.

---

## Session Manager (Protocol)

Defined here so `AgentsManager` can depend on it. The concrete `DefaultSessionManager` implementation, full protocol definition, `SessionEntry` struct, and session map details appear in **Session Storage and Resuming** in [Part 2i](part2i-session.md). Key methods used by `AgentsManager`: `createEntry()` (returns whether the existing identity is still resumable after reconciling cwd/provider), `hasSession()`, `sessionId()`, and `updateSessionId()`. Provider-specific stale detection and launch args live on `AgentAdapter`, not `SessionManager`, so adding a second provider does not force Claude-style resume semantics into the shared binding store.

Phase 3 step #7 builds the full `SessionManager` protocol + `DefaultSessionManager` from Part 2i before step #9 (`AgentsManager`).

---
