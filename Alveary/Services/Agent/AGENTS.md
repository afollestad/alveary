## Agent Runtime And Claude Adapter

These instructions cover the agent runtime and Claude CLI adapter under `Alveary/Services/Agent/`.

## Claude CLI Streaming And Resume

- Claude structured streaming requires `--verbose` alongside `--output-format stream-json`; dropping `--verbose` produces no structured output.
- Do not re-add Claude `--include-hook-events` in `-p` mode; it does not emit useful hook events there, and lifecycle state should continue to derive from the standard event stream and process lifecycle.
- Do not switch `DefaultAgentsManager.readAgentOutput` back to `FileHandle.AsyncBytes.lines` for Claude's stream-json pipe. Keep the `readabilityHandler`-based `PipeLinePump` so final EOF-delimited JSON records without a trailing newline still flush and the UI does not get stuck in a busy/Stop state.
- Claude resume checks must use the canonical cwd. If the expected `~/.claude/projects/<encoded-cwd>/<session>.jsonl` file is missing, `--resume <id>` fails immediately; only then should the adapter fall back to `--session-id <same-id>` to recreate a fresh session file.
- Claude auto-denies `AskUserQuestion` in `-p --output-format stream-json` mode. Keep the app-native prompt/selection UI as the interaction path instead of expecting the CLI to pause for an answer.
- Claude `type: "user"` text events can carry local-command caveat wrappers. Strip only the surrounding `<local-command-caveat>` / `</local-command-caveat>` tags before surfacing the text.
- After caveat-tag stripping, drop the event entirely if the payload is empty before or after stripping so wrapper-only noise never reaches the transcript.
- Claude's request-interruption marker is transcript control flow, not display text:
    - **Map after caveat stripping.** Convert text matching `ConversationInterruption.requestInterruptedByUserMarker` after trimming, case-insensitively, to `.stop(message: ConversationInterruption.displayMessage)`.
    - **Do not surface raw marker text.** The persisted `stop` event renders the centered `Interrupted` transcript note after restore.
    - **Suppress trailing token noise.** Claude may follow the stop marker with an error token whose stop reason is the same interruption. Do not persist or notify that token as an error.
- Streamed top-level `type: "user"` text should surface as an assistant transcript message, not a user bubble. The real user prompt is already inserted locally; any streamed user-text payload is runtime output and should be treated as assistant content after caveat stripping.

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

## Runtime And Config Ownership

- `ClaudeConfigStore` is the sole serialized writer for Claude-owned config in `~/.claude.json`. Provider setup, trust-entry updates, and MCP config writes must continue to flow through it rather than performing direct read/merge/write cycles in feature services.
- `AgentsManager.destroyRuntime()` is the single public owner for destructive runtime teardown. Archive/delete/rollback flows should not reimplement `kill()` + wait loops + direct session-map removal on top of it.
