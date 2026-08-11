## Transcript Grouping

These instructions cover `Alveary/Services/Agent/Transcript/` — `ChatItemGrouper`, which turns the stream of `ConversationEventRecord`s into the `ChatItem`s `ChatTranscriptView` renders, plus the item and note types they carry. Host MCP tool cards are nested and own their own rules: `Alveary/Services/Agent/Transcript/HostToolWidgets/AGENTS.md`.

**Keep a rule here only when the code that would violate it is not the code that documents it.** Mechanism whose only reader is its own file belongs in a doc comment: `groupability(forToolNamed:)`'s groupable and standalone lists, its MCP read-only-verb matcher, and its unknown-defaults-to-standalone invariant; `reemitPendingGroup()`'s emit-without-clearing contract; the assistant-message flush order; `+TranscriptNotes.swift`'s reason for existing; and `+Parsing.swift`'s tool-name and path formatting each carry theirs.

### Grouping

- **Do not auto-close a group when its last in-flight tool completes.** Claude serializes sequential groupable tools as `call → result → call → result …` even for calls that were parallel from the model's perspective, so a completion-triggered seal fractures one burst into many single-entry groups. Groups close only on the explicit close paths.
- **Only a path that appends its own transcript item may call `flushGroup()`.** `append(event:)` ends every cycle in `reemitPendingGroup()` instead; flushing there gives each streamed tool call its own group until the turn-end rebuild coalesces them.
- **Match tool results by `toolId`, not event order alone.** Provider events can persist a `tool_result` timestamped before its `tool_call`; cache unmatched results and consume them when the owning call arrives, or a no-output command stays loading forever.
- **Never render `thinking` events.** Persisted thinking rows stay hidden and live thoughts render only as transient AppKit rows. Do not reintroduce a durable transcript row for thinking without an explicit product ask.
- **A tool that needs its own block type is routed in `handleToolCall`, ahead of the classifier** — `AskUserQuestion`, `TodoWrite`, `Agent`, the plan-mode tools, catalog-matched host tools, and the provider task tools all reach their block that way. Only `handleGenericToolCall` consults `groupability(forToolNamed:)`, so never grow a classifier case to carve out a block type.

### Task Lists

- **One `.taskListBlock` per logical list, keyed by `ConversationEventRecord.toolId`.** A `TodoWrite` with the same tool ID updates that block. Claude also re-emits progress under fresh tool IDs, so a new ID whose content overlaps the latest incomplete block updates it and keeps that block's existing ID; only a genuinely unrelated list appends, and prior blocks stay.
- **Pin only the latest incomplete list.** Route every other row through `appendTranscriptItem(_:)` so it inserts above that block. Once the latest list is complete, later rows append below it in normal transcript order.
- **Use `AgentTaskListReducer` for the provider task tools.** `TaskCreate`, `TaskUpdate`, `TaskList`, and `TaskGet` must not have their Claude wire shape parsed here; their snapshots arrive as persisted `task_list` records and reuse the same block helpers, including when rebuilding from saved rows.
    - Suppress task-only `ToolSearch(select:TaskCreate,TaskUpdate,TaskList,TaskGet)` rows, but keep mixed or unrelated `ToolSearch` rows visible.

### Prompts

- **Default to an `Other` escape hatch.** Parsed `AskUserQuestion` questions synthesize a custom-response option unless the tool input explicitly disables it, so the transcript can capture freeform answers even when Claude offered only fixed labels.
- **Keep one live prompt block per question.** A replacement `AskUserQuestion` replaces the older unanswered prompt and drops the intervening retry chatter; an identical replay *after* the prompt was answered, with no later user message, keeps the original answered block instead of appending a copy under a fresh tool ID.
- **Do not render a second approval card for a prompt.** The deferred `tool_approval` row is persisted for restore and resume bookkeeping only.
- **Clear stale prompts after continuation.** When the provider advances from an unanswered prompt to a non-question approval, mark that prompt handled so it cannot block later approval controls on restore.

### Sub-Agents

- **Keep sub-agent logic in `ChatItemGrouper+SubAgent.swift`.** The split exists to keep `+Processing.swift` under the SwiftLint `file_length` error threshold.
- **Merge sub-agent blocks by child agent ID, never by position.** Approval rows may sit between a live block and the transcript tail, so `removeTrailingPendingBlocksIfNeeded()` must not treat them like generic tool groups.
- **Tolerate out-of-order and late rows.** Agent task completions and `Agent` tool results can precede the matching call — cache them by tool ID — and parent-scoped rows can arrive after a child was evicted from live state, which patches the rendered block rather than dropping the row.
- **Honor hidden completion markers.** Persisted `sub_agent_completed` rows terminalize matching incomplete visible tool rows and sub-agent state; a real `tool_result` stays authoritative for visible output and status.

### Approvals And Plan Mode

- **Render `tool_approval` as its own assistant-side block.** Keep it concise and leave tool input to the tool rows rather than dumping JSON into the approval surface. Ordinary permission approvals pin below active tool and activity rows until resolved, then release at the next non-activity boundary; `AskUserQuestion` and `ExitPlanMode` stay on their special UI paths.
- **Terminalize denied tool rows.** A resolved `.denied` approval may never be followed by a `tool_result`, so complete the matching tool row from the approval status or it stays loading forever.
- **Attach fallback `ExitPlanMode` plans as display only.** AgentCLIKit may interleave a `ToolSearch(select:ExitPlanMode)` row before the approval; skip that lookup, and put the recovered assistant text in `ToolApprovalRequest.planMarkdownFallback` without changing the tool input sent back to Claude.
    - A rendered plan can seed a later markdown `Edit`/`MultiEdit` preview. Mark those `exitPlanModeFollowUp` so the AppKit transcript swaps the tool row for a plan bubble without auto-expanding unrelated markdown mutation rows.
- **Batch parallel approval rows into one item.** Same-session, same-family `tool_approval` rows arriving before their own tool result are one live hook batch, and rendering them separately makes one decision look like it resolved unrelated prompts. Decide membership with `ClaudeApprovalDisplayPolicy`, never a local tool-name list, so path-aware read-only policy settles whether a read, search, or list call is approval-bound.
    - Clear the open batch on assistant and user messages, errors, stop notes, and a tool result for a tool in the batch. Unrelated read-only results may interleave between parallel hooks and must not split it.

### Transcript Notes

- **Use typed transcript notes for subtle lifecycle rows.** `Interrupted`, session handoff, provider context compaction, steering markers, and plan-mode transitions all flow through `ChatItem.transcriptNote` so grouping, restore, alignment, and future note-style events share one representation.
- **Replace compaction starts with terminal notes.** A later completed or failed record with the same compaction ID replaces the `context_compaction_started` row instead of appending beneath it.
