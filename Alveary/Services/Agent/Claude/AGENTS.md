## Claude Provider

These instructions cover Claude provider support under `Alveary/Services/Agent/Claude/`.

- Claude HTTP hook listener, settings generation, and approval policy code lives under `Hooks/`; follow `Hooks/AGENTS.md` for that subsystem.
- `ClaudeConfigStore` is the sole serialized writer for Claude-owned config in `~/.claude.json`. Provider setup, trust-entry updates, and MCP config writes must continue to flow through it rather than performing direct read/merge/write cycles in feature services.
- `ClaudeConfigStore` owns Claude config observation. UI should use its replaying snapshot stream, `.claudeConfigChanged`, or `ProviderSetupService` trust APIs instead of adding file watchers.
- Claude structured streaming requires `--verbose` alongside `--output-format stream-json`; dropping `--verbose` produces no structured output.
- Do not re-add Claude `--include-hook-events` in `-p` mode; it does not emit useful hook events there, and lifecycle state should continue to derive from the standard event stream and process lifecycle.
- Decode assistant-message `usage` into interim token rows so context usage updates while Claude is blocked on app-native prompts. These rows use `ConversationEvent.interimUsageStopReason` and must not end the active turn.
- Claude resume checks must use the canonical cwd. If the expected `~/.claude/projects/<encoded-cwd>/<session>.jsonl` file is missing, `--resume <id>` fails immediately; only then should the adapter fall back to `--session-id <same-id>` to recreate a fresh session file.
- Keep `ClaudeAdapter.swift` focused on launch/session/message concerns. Put JSON decoding in `ClaudeAdapter+Decoding.swift`, system/task events in `ClaudeAdapter+SystemEvents.swift`, and hook attachment decoding in `ClaudeAdapter+Attachments.swift`.
- Treat Claude `permissionMode` updates from the stream as the live runtime source of truth:
    - **Sync `system/init` and `system/status`.** When Claude emits `permissionMode`, update both the in-memory runtime mode and the persisted thread picker state.
    - **Keep plan resumes in plan.** If a deferred `ExitPlanMode` approval is pending, respawn Claude with `permissionMode: "plan"` even if the stored thread mode is stale, or Claude will reject the tool with `You are not in plan mode.`
    - **Restore fallback mode after plan exit.** Track the last non-plan mode so Alveary can fall back to it if `ExitPlanMode` succeeds but no later status event arrives before the turn resolves.
- Claude `type: "user"` text events can carry local-command caveat wrappers. Strip only the surrounding `<local-command-caveat>` / `</local-command-caveat>` tags before surfacing the text.
- After caveat-tag stripping, drop the event entirely if the payload is empty before or after stripping so wrapper-only noise never reaches the transcript.
- Claude's request-interruption marker is transcript control flow, not display text:
    - **Map after caveat stripping.** Convert text matching `ConversationInterruption.requestInterruptedByUserMarker` after trimming, case-insensitively, to `.stop(message: ConversationInterruption.displayMessage)`.
    - **Do not surface raw marker text.** The persisted `stop` event renders the centered `Interrupted` transcript note after restore.
    - **Suppress trailing token noise.** Claude may follow the stop marker with an error token whose stop reason is the same interruption. Do not persist or notify that token as an error.
- Streamed top-level `type: "user"` text should surface as an assistant transcript message, not a user bubble. The real user prompt is already inserted locally; any streamed user-text payload is runtime output and should be treated as assistant content after caveat stripping.
- Decode both `stop_reason == "tool_deferred"` plus `deferred_tool_use` and `attachment.type == "hook_deferred_tool"` into a concise `tool_approval` record so restart can restore the pending action.
- A `hook_deferred_tool` attachment should also emit a zero-usage `tool_deferred` token event so the runtime uses the same stop/teardown path as result-form deferrals.
- Once a Claude adapter instance has emitted a deferred-tool event, ignore later JSON records from that adapter instance; process teardown is asynchronous and the pipe reader can otherwise race buffered fallback tool calls into the transcript.
- Decode `hook_non_blocking_error` attachments into typed tool-approval failures when a `toolUseID` is present, persist a transcript error for visibility, supersede the matching pending approval, and consume the manager's matching pending-live approval count so later approvals do not take the live path for a dead hook.
