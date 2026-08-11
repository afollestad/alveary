## Alveary Host MCP Server

The tools Alveary exposes *to* the agent. Not `Alveary/Services/MCP/`, which configures the third-party MCP servers the provider CLIs connect to. Transport, registration, and loopback security live in `AgentCLIKit`'s `Sources/AgentCLIKit/MCP/AGENTS.md`.

### Composition

- Keep this folder feature-neutral. A feature owns its catalog and handler in its own folder (`Alveary/Services/Scheduled/`, `Alveary/Services/Threads/`, `Alveary/Services/PullRequests/`) and enrolls here.
- Enroll a feature in two places: its `HostToolFeatureCatalog` in `AlvearyHostToolCatalog.featureCatalogs`, and its `HostToolFeature` handler in `AppComponent+HostMCP.swift`. Definitions are consumed statically at spawn; handlers need DI, which is why the two lists exist.
- **Keep the dispatcher's feature list a closure.** `hostToolDispatcher` is constructed while `agentCLIKitRuntime` is being built, so resolving a feature that reaches `agentsManager` — `ThreadHostToolService` does, via `ThreadLifecycleService` — recurses back through the runtime getter and overflows the stack during DI. `HostToolDispatcher` resolves features on the first call instead, by which time a provider process exists.
- `AlvearyHostToolCatalog.serverName` is the only place the server name is spelled. AgentCLIKit registers one server per process, so every feature shares that identity, the composed instructions, and `HostToolDispatcher`'s routing.
- Tool names are unique across features. Composition traps on a duplicate, and `AlvearyHostToolCatalogTests` proves every advertised tool reaches a handler — that parity is the one real risk of splitting static catalogs from DI-built handlers.
- Keep each `instructionsFragment` to what its own tools need; the preamble already forbids substitutes, invented tools, and unasked-for calls.
- **Keep every tool `title` and `description` short.** The whole catalog ships in each turn's system prompt, so prose costs tokens on every request; state what the tool does, its refusals, and the sibling it loses to, and drop rationale the model does not act on.
- Enrolled today: `ScheduledTaskHostToolCatalog` (`Alveary/Services/Scheduled/`), `ThreadHostToolCatalog` (`Alveary/Services/Threads/`), and `PullRequestHostToolCatalog` (`Alveary/Services/PullRequests/HostTools/`). A tool one feature directs the model toward may live in another — `propose_scheduled_task` names `list_projects` and `list_threads` — which is safe only because exposure is all-or-nothing per turn.
- **Derive an exact-retry key through `HostToolDeduplication`, and store its receipt through `HostToolReceiptLedger`.** Every mutating feature keys and prunes its ledger the same way, so two features cannot disagree on what "the same call" is or on when a recorded result stops being replayable.
- **Keep the preamble honest about what the server reaches.** It said the tools act on Alveary alone; once pull requests started reaching GitHub, that framing made `gh` and a web search look like the right way to answer a GitHub question, and models took it. "Never touches the user's code or files" is the part that stays true of every feature.
- **Name the substitutes a tool actually loses to.** A general "do not use shell commands" did not stop `gh pr list`; the preamble now rules out the gh CLI, git, web search, and other MCP servers by name. A new feature whose job overlaps a well-known CLI owes that CLI a mention.

### Handler Contract

- **Bind identity from `AgentHostToolCallContext`, never from arguments.** Conversation, provider, process token, and request ID are trusted runtime state; a tool argument naming any of them is a steering vector.
- **Resolve the source first, through `HostToolSourceResolver`.** A caller Alveary cannot place reads nothing. Feature eligibility layers on top; it never replaces that check.
- **Validate every key and type through `StrictHostToolObject`,** whatever the advertised JSON Schema promised. `requireOnly` allowlists keys so an unadvertised field is refused rather than ignored.
- **Fill `text` and `structuredContent` both.** Codex surfaces only the text fallback.
- **Require confirmation only where the change is not reversible.** A reversible mutation applies immediately and says so; each feature owns which of its actions qualify.
- Nest schema unions via `HostToolSchema.strictNestedUnionObject` — Claude drops tool definitions with a union at the input-schema root.

### Exposure

- Exposure is all-or-nothing per turn: `ConversationViewModel.hostToolConfiguration` attaches the whole merged catalog or none of it, and suppresses it for continuations and `ConversationState.hostToolsDisabled`. Automated scheduled turns attach the catalog like ordinary outbound; which tools serve them is each feature's service gate (thread and scheduling mutations refuse, pull requests refuse only `close_pr`).
- Launch failure retries once without tools through `HostToolFallbackClassifier`; only a current accepting event buffer may disable a replacement runtime.
- Providers report a called tool either bare or prefixed with the server name. Match through `AlvearyHostToolCatalog.matches`; see `Alveary/Services/Agent/Transcript/HostToolWidgets/AGENTS.md` for how descriptors use it.
