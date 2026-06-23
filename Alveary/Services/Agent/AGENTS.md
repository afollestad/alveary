## Agent Services

These instructions cover provider-neutral interfaces under `Alveary/Services/Agent/`.

- Runtime process management lives under `Runtime/`; follow `Runtime/AGENTS.md` for `DefaultAgentsManager`, event buffers, lifecycle, and deferred-tool runtime behavior.
- Claude provider runtime, stream decoding, hook transport, provider approval policy, transcript paths, and transcript inspection live in `AgentCLIKit`; Alveary bridges those services but does not duplicate them.
- Claude approval persistence and UI display policy lives under `Claude/Approvals/`; follow `Claude/Approvals/AGENTS.md` for durable session approvals, approval selections, and approval-row display rules.
- Transcript grouping code lives under `Transcript/`; follow `Transcript/AGENTS.md` for `ChatItemGrouper` behavior.
- `ContextWindowCache` is app-level provider metadata, not conversation history. Keep it in the JSON-backed cache under Application Support, key entries by `providerID:model`, and treat it as advisory: provider-reported result data always wins. Cache writes should stay best-effort/background so turn completion and transcript persistence do not wait on disk I/O.
- Use `ContextTokenAccounting` for context-window percentages and automatic handoff thresholds. Claude/default cache-read tokens are additive; Codex cached-input tokens are already included in input tokens and must not be added again. Correct legacy Codex rows at read time instead of migrating SwiftData.
- Provider status and model options come from `AgentCLIKit.AgentProviderDiscoveryService`. Keep settings and composer provider lists wired to that service instead of duplicating Claude/Codex availability or model lists in UI code.
- Speed mode is provider-reported capability from `AgentCLIKit.AgentProviderCapabilities.supportsSpeedMode`. Do not add app-owned provider/model speed maps; Claude stays Standard unless AgentCLIKit reports otherwise.
- Project-level one-shot prompts should use `AgentCLIKit.AgentOneShotPromptRunning` directly. Keep active-thread hidden commit
  generation runtime-backed so it can use existing thread context.
- Plan mode is collaboration state, not an approval policy. Alveary should pass it through `AgentSpawnConfig.planModeEnabled`/AgentCLIKit `collaborationMode` and keep `"plan"` out of permission-picker option sources.
- Keep denied `ExitPlanMode` copy in shared `ExitPlanModeDenialPolicy`; add provider-specific transport guidance there only when a provider cannot reliably infer Alveary's host-side plan-mode state.
- Provider task-list snapshots should persist through Alveary's provider-neutral `task_list` event records; keep provider-specific task parsing in `AgentCLIKit`. Treat interrupted task rows as terminal for the stopped turn, but let later provider snapshots or updates reactivate them.
- Project trust policy is app-owned, but provider trust state comes from `AgentCLIKit.AgentProjectTrustService`. Keep prompt UI, auto-trust, first-thread gating, and denial cleanup in Alveary while avoiding direct provider config reads.
- Provider MCP config reads/writes should route through AgentCLIKit config stores for providers that own their config format, including Claude `.claude.json` and Codex `.codex/config.toml`.
- Provider-native archive/unarchive is a best-effort companion to Alveary's local archive and delete lifecycle. Resolve records through `AgentSessionStore`, then route through `ProviderSessionActionService`; do not let provider action failures roll back local archive, restore, or delete state. Delete paths should archive only known provider sessions and treat missing bindings as nothing to clean up.

## Cross-Folder Debugging

- When investigating missing, duplicate, or stuck transcript rows, cross-reference the provider transcript or AgentCLIKit runtime events, persisted runtime events, and SwiftData instead of trusting any single source:
    - **Start from the conversation.** Identify the `Conversation.id`, provider session ID, and canonical cwd so the matching provider transcript path is unambiguous.
    - **Compare raw and decoded events.** Check whether the provider transcript contains the expected raw records or hook attachments before assuming the adapter decoded or dropped them incorrectly.
    - **Inspect persisted rows.** Query `ConversationEventRecord`s for that conversation ordered by `timestamp` and primary key so event order, `type`, `toolId`, `toolName`, `stopReason`, and `toolApprovalStatus` can be compared against the raw transcript.
    - **Check live runtime state.** If the UI shows a pending approval or spinner, also check `AgentCLIKit.AgentRuntimeStatus` for the conversation; stale runtime state can explain prompts that render but do not resume.
    - **Keep scope here.** Document cross-source transcript debugging in this file; use `Alveary/Data/AGENTS.md` only for SwiftData model invariants or schema-level persistence contracts.
