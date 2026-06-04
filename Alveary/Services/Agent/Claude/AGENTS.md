## Claude Provider

These instructions cover Claude-related Alveary code under `Alveary/Services/Agent/Claude/`.

- Provider launch, hook transport, stream decoding, Claude session paths, provider approval policy, and transcript inspection live in `AgentCLIKit`. Do not reintroduce local Claude adapters, decoders, hook listeners, generated hook settings, launch tokens, or transcript-path encoders here.
- Alveary-owned durable approval persistence and approval display policy lives under `Approvals/`; follow `Approvals/AGENTS.md` for that subsystem.
- `AgentCLIKit.ClaudeConfigStore` is the sole serialized writer and observer for Claude-owned config in `~/.claude.json`. Provider setup, trust-entry updates, and MCP config writes must flow through `AgentCLIKit`; Alveary owns only prompt policy and UI behavior.
- UI should observe provider-neutral project-trust updates through `ProviderSetupService` instead of adding Claude-specific notifications or file watchers.
- Claude structured streaming details and `--include-hook-events` behavior belong in `AgentCLIKit` docs/tests, not Alveary.
- Decode assistant-message `usage` into interim token rows so context usage updates while Claude is blocked on app-native prompts. These rows use `ConversationEvent.interimUsageStopReason` and must not end the active turn.
- Claude resume checks and transcript path construction must use `AgentCLIKit.ClaudePathEncoder`.
- Treat Claude `permissionMode` updates from the stream as the live runtime source of truth:
    - **Sync `system/init` and `system/status`.** When Claude emits `permissionMode`, update both the in-memory runtime mode and the persisted thread picker state.
    - **Keep plan resumes in plan.** If a deferred `ExitPlanMode` approval is pending, respawn Claude with `permissionMode: "plan"` even if the stored thread mode is stale, or Claude will reject the tool with `You are not in plan mode.`
    - **Restore fallback mode after plan exit.** Track the last non-plan mode so Alveary can fall back to it if `ExitPlanMode` succeeds but no later status event arrives before the turn resolves.
- Claude event decoding details, including local-command caveats, interruption markers, deferred-tool attachments, hook failures, and context-compaction events, belong in `AgentCLIKit` tests and docs.
