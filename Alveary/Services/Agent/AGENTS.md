## Agent Runtime And Claude Adapter

These instructions cover the agent runtime and Claude CLI adapter under `Alveary/Services/Agent/`.

- Claude HTTP hook listener, settings generation, and approval policy code lives under `Hooks/`; follow `Hooks/AGENTS.md` for that subsystem.

## Claude CLI Streaming And Resume

- Claude structured streaming requires `--verbose` alongside `--output-format stream-json`; dropping `--verbose` produces no structured output.
- Do not re-add Claude `--include-hook-events` in `-p` mode; it does not emit useful hook events there, and lifecycle state should continue to derive from the standard event stream and process lifecycle.
- Do not switch `DefaultAgentsManager.readAgentOutput` back to `FileHandle.AsyncBytes.lines` for Claude's stream-json pipe. Keep the `readabilityHandler`-based `PipeLinePump` so final EOF-delimited JSON records without a trailing newline still flush and the UI does not get stuck in a busy/Stop state.
- Claude resume checks must use the canonical cwd. If the expected `~/.claude/projects/<encoded-cwd>/<session>.jsonl` file is missing, `--resume <id>` fails immediately; only then should the adapter fall back to `--session-id <same-id>` to recreate a fresh session file.
- Hook-gate `AskUserQuestion` in `-p --output-format stream-json` mode:
    - **Defer the tool first.** Let `PreToolUse` return `defer` so Claude stops before fabricating a fallback message about the question being dismissed.
    - **Resume with `updatedInput`.** When the user answers in Alveary's prompt UI, resume the deferred tool with `allow` plus an `answers` object added to the original `questions` payload instead of sending a normal follow-up chat message.
    - **Default to an `Other` escape hatch.** Parsed prompt questions should synthesize a custom-response option unless the tool input explicitly disables it, so the transcript UI can capture freeform answers even when Claude only provided fixed labels.
    - **Hide the approval row.** Persist the deferred `tool_approval` row for restore/resume bookkeeping, but do not render a separate tool-approval card when the transcript already shows the prompt block for that same `AskUserQuestion`.
    - **Prefer the latest unanswered prompt.** If Claude still emits retry chatter and a replacement `AskUserQuestion`, collapse the transcript back to one live prompt block by replacing the older unanswered prompt and dropping any intervening prompt-retry text.
    - **Ignore identical answered replays.** If Claude replays the same parsed question set after the prompt was already answered and no later user message exists, keep the original answered prompt block instead of appending a second copy under a fresh tool id.
- While an app-native `AskUserQuestion` prompt is unanswered, treat it as the only actionable pending interaction for that conversation:
    - **Reject deferred tool approvals.** Do not let `approveToolUse` / `denyToolUse` resume Claude while the prompt still needs an answer.
    - **Let the prompt answer proceed.** Prompt submission should still be able to send the structured answer even if a deferred tool approval row is present.
    - **Supersede the stale approval row after sending the answer.** Once the prompt answer is accepted locally, any still-pending approval from that turn should be marked `superseded` so only the post-answer interaction history remains actionable.
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
- Claude tool deferral is a normal turn stop:
    - **Persist the approval request.** Decode `stop_reason == "tool_deferred"` plus `deferred_tool_use` into a concise `tool_approval` record so restart can restore the pending action.
    - **Stop the live runtime immediately.** As soon as the stream reports `tool_deferred`, tear down the current Claude process while preserving the session so Claude cannot retry the deferred tool or invent fallback text before the process exits on its own.
    - **Ignore trailing events from that runtime.** Once a given stream generation emits `tool_deferred`, drop any later events from the same live process instead of letting buffered fallback chatter leak into the transcript before teardown completes.
    - **Route deferred `AskUserQuestion` back through the prompt UI.** On answer, resume the deferred tool with `updatedInput` rather than treating the answer as a new user chat message.
    - **Persist final approval state on the same row.** Once a resumed deferred turn resolves, write the final approve/deny status to the associated `tool_approval` record; do not add sidecar approval state.
    - **Downgrade replaced approval rows.** If a newer deferred tool use arrives before an older unresolved `tool_approval` row is resolved, persist the older row as `superseded` unless it already had a concrete local decision that should be preserved as approved/denied.
    - **Do not treat it as an error.** End the active turn without setting `lastTurnError`; queued messages must remain paused until the approval resumes and finishes the deferred turn.
    - **Resume same session.** Approval/denial records a one-shot hook decision keyed by Claude `session_id + tool_use_id`, then respawns the same session without forking.
    - **Session approval is additive.** `Approve for session` also records a generic session approval grant keyed by provider, conversation ID, and Claude `session_id`, but it still records the one-shot decision for the currently deferred tool use so the in-flight resume can proceed immediately.
- Certain Claude tool lifecycles should render as centered transcript notes instead of tool pills:
    - **Keep pending transitions off-screen.** `EnterPlanMode` and `ExitPlanMode` should not surface as standalone tool rows while they are still in flight.
    - **Use centered notes for resolved plan transitions.** Successful `EnterPlanMode` / `ExitPlanMode` results should emit centered notes (`Entered plan mode` / `Exited plan mode`), and denied `ExitPlanMode` should emit `Staying in plan mode`.
    - **Preserve real failures.** If one of those tool results actually fails for a non-denial reason, fall back to the normal standalone tool rendering so users can still inspect the failure state and output.
- When Claude reaches a later root-level tool interaction, earlier pending root-level tool rows should no longer keep spinning:
    - **Implicitly finish prior rows on later approval.** If a different tool reaches `tool_approval`, mark any older pending root-level tool rows as complete even if their explicit `tool_result` arrived too late or was lost around the deferred transition.
    - **Still allow late patching.** Do not remove those rows; late `tool_result` events should still be able to fill in output or error state afterward.

## ChatItem Grouping

`ChatItemGrouper` turns the stream of `ConversationEventRecord`s into a list of `ChatItem`s rendered by `ChatTranscriptView`. Rules:

- Generic tool calls split into two visual shapes via `ChatItemGrouper.groupability(forToolNamed:)`:
    - **Groupable (`.toolGroup`):** `Read`, `Grep`, `Glob`, `WebFetch`, `WebSearch`, and MCP tools whose trailing segment starts with a read-only verb (`read_`, `list_`, `get_`, `search_`, `fetch_`, `describe_`, `query_`, `lookup_`, `show_`, `check_`).
    - **Standalone (`.standaloneTool`):** `Write`, `Edit`, `MultiEdit`, `NotebookEdit`, `Bash`, and anything unknown. Unknown defaults to standalone so a mutating tool can never be silently folded under a group header.
    - **Skip the classifier for `TodoWrite`, `AskUserQuestion`, `Agent`.** Those route to `.taskListBlock` / `.promptBlock` / `.subAgentBlock` and bypass the generic tool pipeline.
- **Do not auto-close a group when its last in-flight tool completes.** Claude's stream serializes sequential groupable tools as `call → result → call → result …` (even for "parallel" calls from the model's perspective). A completion-triggered seal fractures that burst into many single-entry groups, which is what users actually see on disk. Let groups close only on the explicit close paths below.
- **`append(event:)` must re-emit without clearing.** Each streaming event calls `reemitPendingGroup()` (emit-only) rather than `flushGroup()` (emit + clear) at the end of the cycle — otherwise every tool call spawns its own single-entry group during streaming and they only coalesce on the forced full rebuild at turn end. Only close paths (assistant message when all tools done, user message, error, standalone tool, sub-agent, prompt, task list, interrupted stop note) may call `flushGroup()`.
- **Never render `thinking` events.** `process(_:)` falls through on `type == "thinking"`. The active-turn spinner in `ChatTranscriptView` covers the "something is happening" affordance. Do not reintroduce a transcript row for thinking without an explicit product ask.
- **Assistant messages close a group only when every pending tool has finished.** Completed batch → assistant is summarizing, so flush first and the message lands below the group. Still-running batch → Claude is introducing the next wave, so leave the group open and let `removeTrailingPendingBlocksIfNeeded` + outer `flushGroup()` re-emit the trailing `.toolGroup` below the message. Every other close-eligible event (user message, error, standalone tool, sub-agent, prompt, task list, interrupted stop note) always closes the group.
- `TodoWrite` task-list pinning:
    - **Key blocks by tool ID.** `ConversationEventRecord.toolId` comes from Claude's `tool_use.id`; use it for the task-list block ID when present.
    - **Replace matching blocks.** A TodoWrite with the same tool ID updates the existing `.taskListBlock` instead of appending a duplicate.
    - **Deduplicate logical updates.** Claude may emit TodoWrite progress updates with new tool IDs. If the task content overlaps the latest incomplete task-list block, update that block and preserve its existing ID instead of appending another copy.
    - **Keep distinct TodoWrite history.** A TodoWrite with a new tool ID appends a new `.taskListBlock`; do not remove unrelated prior blocks.
    - **Route appends through `appendTranscriptItem(_:)`.** User, assistant, tool, sub-agent, prompt, error, and interrupted-note rows should insert above the latest incomplete `.taskListBlock`.
    - **Pin only the latest incomplete list.** Once a newer task list arrives, older lists stay in transcript history behind it. If the latest task list is complete, later rows append below it in normal transcript order.
- **Keep sub-agent logic in `ChatItemGrouper+SubAgent.swift`.** The file owns start/progress/complete handlers, agent tool-call routing, and sub-agent patching helpers. The split exists to keep `+Processing.swift` under the SwiftLint file-length limit.
- **Render `tool_approval` as its own assistant-side block.** Flush any pending tool group/sub-agent block first, keep the block concise, and leave detailed tool input to existing tool rows rather than dumping JSON into the approval surface.
- **Use typed centered transcript notes for subtle lifecycle rows.** `Interrupted` and successful plan-mode transitions should flow through the same `ChatItem.centeredNote` path so transcript grouping, restore, and future note-style events share one representation.

## Runtime And Config Ownership

- `ClaudeConfigStore` is the sole serialized writer for Claude-owned config in `~/.claude.json`. Provider setup, trust-entry updates, and MCP config writes must continue to flow through it rather than performing direct read/merge/write cycles in feature services.
- `AgentsManager.destroyRuntime()` is the single public owner for destructive runtime teardown. Archive/delete/rollback flows should not reimplement `kill()` + wait loops + direct session-map removal on top of it.
