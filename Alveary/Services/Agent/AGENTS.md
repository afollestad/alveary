## Agent Services

These instructions cover provider-neutral interfaces under `Alveary/Services/Agent/`.

- Runtime process management lives under `Runtime/`; follow `Alveary/Services/Agent/Runtime/AGENTS.md` for `DefaultAgentsManager`, event buffers, and lifecycle, and `Alveary/Services/Agent/Runtime/ToolApproval/AGENTS.md` for live and deferred tool approval.
- Claude provider runtime, stream decoding, hook transport, provider approval policy, transcript paths, and transcript inspection live in `AgentCLIKit`; Alveary bridges those services but does not duplicate them.
- Claude approval persistence and UI display policy lives under `Claude/Approvals/`; follow `Alveary/Services/Agent/Claude/Approvals/AGENTS.md` for durable session approvals, approval selections, and approval-row display rules.
- Transcript grouping code lives under `Transcript/`; follow `Alveary/Services/Agent/Transcript/AGENTS.md` for `ChatItemGrouper` behavior.

### Context And Usage

- `ContextWindowCache` is app-level provider metadata, not conversation history. Keep it in the JSON-backed cache under Application Support, key entries by `providerID:model`, and treat it as advisory: provider-reported result data always wins. Cache writes should stay best-effort/background so turn completion and transcript persistence do not wait on disk I/O.
- Use `ContextTokenAccounting` for context-window percentages and automatic handoff thresholds. Claude/default cache-read tokens are additive; Codex cached-input tokens are already included in input tokens and must not be added again. Correct legacy Codex rows at read time instead of migrating SwiftData.

### Provider Capabilities

- Provider status and model options come from `AgentCLIKit.AgentProviderDiscoveryService`. Keep settings and composer provider lists wired to that service instead of duplicating Claude/Codex availability or model lists in UI code.
    - **Take typed short model names from the provider.** `AgentModelOption.shortName` is the alias users type (`opus`, `sol`); it falls back to `id` when a provider has no unambiguous alias. Do not derive or slugify short names app-side, and do not assume they differ from `id`.
        - **Resolve a stored selection by short name too.** A value persisted as `opus` matches no option id now that Claude lists pinned versions, and `AgentModelOptionSelection.option(in:matching:)` without that fallback resets the user's model.
    - **Cold-path model-option fallbacks take `AgentDefaultModelOptions.staticOptions(for:)`, never `providerDefault(for:)`.** The one-row placeholder resolves no persisted selection, so pre-discovery UI flashed raw ids like `claude-opus-5` and reset stored models.
    - **Reach discovery through `CachingAgentProviderDiscoveryService`**, wired as `AppComponent.cachedAgentProviderDiscoveryService`; the raw service spawns `which`, a login shell, `--version`, and a Codex app-server session per read, which every thread creation paid for. Nothing but the decorator should call the raw one.
        - **Only `providerStatuses(projectURL: nil)` is cached**, with in-flight coalescing. A project-scoped read carries that project's trust state, and the two filtered accessors have no callers, so all of them pass through. Enablement is never cached — `ThreadDefaultResolver` reads it from `AppSettings` each time.
        - **A read never blocks once any snapshot exists.** The TTL bounds staleness, not latency: an aged snapshot is served immediately and refreshed behind it, because blocking put the fan-out on the New Thread click. Only `warm()` waits, so keep its launch, wake, and pull-request call sites.
        - **Settings invalidates before it reads**, because installing a CLI or finishing a setup happens on that screen; wake invalidates then re-warms. A probe already running when `invalidate()` lands answers its caller but is not stored.
- **Claude's setup readiness is auth-backed, and an inconclusive probe reports ready.** `ClaudeProviderSetup` runs `claude auth status`, so a signed-out CLI reaches every `isSetupReady` gate as `.needsSetup` before work starts; a probe that times out or cannot decode reports ready, because locking the user out of a working CLI is worse than one doomed turn.
    - **A credential that dies mid-turn arrives typed.** AgentCLIKit codes it `providerAuthenticationRequired`; `ProviderSignInService` is what acts on it, so do not string-match provider auth text app-side.
- Speed mode is provider-reported capability from `AgentCLIKit.AgentProviderCapabilities.supportsSpeedMode`. Do not add app-owned provider/model speed maps; Claude stays Standard unless AgentCLIKit reports otherwise.
- Project-level one-shot prompts should use `AgentCLIKit.AgentOneShotPromptRunning` directly. Keep active-thread hidden commit
  generation runtime-backed so it can use existing thread context.
- Plan mode is collaboration state, not an approval policy. Alveary should pass it through `AgentSpawnConfig.planModeEnabled`/AgentCLIKit `collaborationMode` and keep `"plan"` out of permission-picker option sources.
- Keep denied `ExitPlanMode` copy in shared `ExitPlanModeDenialPolicy`; add provider-specific transport guidance there only when a provider cannot reliably infer Alveary's host-side plan-mode state.
- Provider task-list snapshots should persist through Alveary's provider-neutral `task_list` event records; keep provider-specific task parsing in `AgentCLIKit`. Treat interrupted task rows as terminal for the stopped turn, but let later provider snapshots or updates reactivate them.
- Project trust policy is app-owned, but provider trust state comes from `AgentCLIKit.AgentProjectTrustService`. Keep prompt UI, auto-trust, first-thread gating, and denial cleanup in Alveary while avoiding direct provider config reads.
- Provider MCP config reads/writes should route through AgentCLIKit config stores for providers that own their config format, including Claude `.claude.json` and Codex `.codex/config.toml`.

### App Shots

- App shots are provider-strategy transport, not visible composer text. Codex app shots use `localImage` attachments with `CodexInputMetadata.isAppshot`; Claude app shots keep text-only transport with hidden AX context and an absolute Markdown screenshot reference. Unsupported providers must block instead of downgrading app shots to ordinary Markdown image links.
- Keep app-shot capture preparation provider-neutral and storage-independent: window metadata, AX text, and PNG data are prepared first, then stored for the claimed destination through the shared attachment store. Stage through `ConversationState.stageAppShot` so pre-mount destinations update composer non-empty state without requiring a `ChatView`.
- Keep app-shot screenshots in the conversation attachment store under Application Support. Preserve them while staged, queued, retryable, or transcript-visible, and include the store root in Claude `--add-dir` launch arguments when needed.

### Provider Sessions

- Provider-native archive/unarchive/delete is a best-effort companion to Alveary's local archive and delete lifecycle. Resolve records through `AgentSessionStore`, then route through `ProviderSessionActionService`; do not let provider action failures roll back local archive, restore, or delete state.
- **Keep missing bindings visible on delete.** A conversation whose provider session cannot be resolved leaves a live provider-side session behind, so the resolution carries it through for a diagnostic instead of dropping it.
    - **Except when the thread never started.** `ThreadLifecycleService` sources `ProviderSessionConversationSnapshot.hasStartedProviderSession` from `hasCompletedInitialSetup`, and resolution drops those unresolved bindings — a thread whose first spawn failed has no session to strand.
- **Gate every action on its capability**, deletion included. A provider without native deletion is skipped, not handed to the adapter's validate-only default that reports success having done nothing.
- **A record retires its whole lineage.** `AgentSessionRecord.supersededProviderSessionIds` travels with the record, so removing one — as session handoff does — must archive it first or the lineage becomes unreachable.

## Cross-Folder Debugging

- When investigating missing, duplicate, or stuck transcript rows, cross-reference the provider transcript or AgentCLIKit runtime events, persisted runtime events, and SwiftData instead of trusting any single source:
    - **Start from the conversation.** Identify the `Conversation.id`, provider session ID, and canonical cwd so the matching provider transcript path is unambiguous.
    - **Compare raw and decoded events.** Check whether the provider transcript contains the expected raw records or hook attachments before assuming the adapter decoded or dropped them incorrectly.
    - **Inspect persisted rows.** Query `ConversationEventRecord`s for that conversation ordered by `timestamp` and primary key so event order, `type`, `toolId`, `toolName`, `stopReason`, and `toolApprovalStatus` can be compared against the raw transcript.
    - **Check live runtime state.** If the UI shows a pending approval or spinner, also check `AgentCLIKit.AgentRuntimeStatus` for the conversation; stale runtime state can explain prompts that render but do not resume.
    - **Keep scope here.** Document cross-source transcript debugging in this file; use `Alveary/Data/AGENTS.md` only for SwiftData model invariants or schema-level persistence contracts.
