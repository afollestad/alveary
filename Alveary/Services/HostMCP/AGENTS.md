## Alveary Host MCP Server

The tools Alveary exposes *to* the agent. Not `Alveary/Services/MCP/`, which configures the third-party MCP servers the provider CLIs connect to. Transport, registration, and loopback security live in `AgentCLIKit`'s `Sources/AgentCLIKit/MCP/AGENTS.md`.

### Composition

- Keep this folder feature-neutral. A feature owns its catalog and handler in its own folder (`Services/Scheduled/`, `Services/Threads/`) and enrolls here.
- Enroll a feature in two places: its `HostToolFeatureCatalog` in `AlvearyHostToolCatalog.featureCatalogs`, and its `HostToolFeature` handler in `AppComponent+HostMCP.swift`. Definitions are consumed statically at spawn; handlers need DI, which is why the two lists exist.
- **Keep the dispatcher's feature list a closure.** `hostToolDispatcher` is constructed while `agentCLIKitRuntime` is being built, so resolving a feature that reaches `agentsManager` — `ThreadHostToolService` does, via `ThreadLifecycleService` — recurses back through the runtime getter and overflows the stack during DI. `HostToolDispatcher` resolves features on the first call instead, by which time a provider process exists.
- `AlvearyHostToolCatalog.serverName` is the only place the server name is spelled. AgentCLIKit registers one server per process, so every feature shares that identity, the composed instructions, and `HostToolDispatcher`'s routing.
- Tool names are unique across features. Composition traps on a duplicate, and `AlvearyHostToolCatalogTests` proves every advertised tool reaches a handler — that parity is the one real risk of splitting static catalogs from DI-built handlers.
- Keep each `instructionsFragment` to what its own tools need; the preamble already forbids substitutes, invented tools, and unasked-for calls.
- Enrolled today: `ScheduledTaskHostToolCatalog` (`Services/Scheduled/`) and `ThreadHostToolCatalog` (`Services/Threads/`). A tool one feature directs the model toward may live in another — `propose_scheduled_task` names `list_projects` and `list_threads` — which is safe only because exposure is all-or-nothing per turn.
- **Derive an exact-retry key through `HostToolDeduplication`.** Every mutating feature keys its receipt ledger the same way, so two features cannot disagree on what "the same call" is.

### Handler Contract

- **Bind identity from `AgentHostToolCallContext`, never from arguments.** Conversation, provider, process token, and request ID are trusted runtime state; a tool argument naming any of them is a steering vector.
- **Resolve the source first, through `HostToolSourceResolver`.** A caller Alveary cannot place reads nothing. Feature eligibility layers on top; it never replaces that check.
- **Validate every key and type through `StrictHostToolObject`,** whatever the advertised JSON Schema promised. `requireOnly` allowlists keys so an unadvertised field is refused rather than ignored.
- **Fill `text` and `structuredContent` both.** Codex surfaces only the text fallback.
- **Require confirmation only where the change is not reversible.** A reversible mutation applies immediately and says so; each feature owns which of its actions qualify.
- Nest schema unions via `HostToolSchema.strictNestedUnionObject` — Claude drops tool definitions with a union at the input-schema root.

### Exposure

- Exposure is all-or-nothing per turn: `ConversationViewModel.hostToolConfiguration` attaches the whole merged catalog or none of it, and suppresses it for continuations, automated scheduled turns, and `ConversationState.hostToolsDisabled`.
- Launch failure retries once without tools through `HostToolFallbackClassifier`; only a current accepting event buffer may disable a replacement runtime.
- Providers report a called tool either bare or prefixed with the server name. Match through `AlvearyHostToolCatalog.matches`; see `Services/Agent/Transcript/AGENTS.md` for how descriptors use it.
