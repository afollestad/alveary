## Agent Services

These instructions cover provider-neutral interfaces under `Alveary/Services/Agent/`.

- Runtime process management lives under `Runtime/`; follow `Runtime/AGENTS.md` for `DefaultAgentsManager`, event buffers, process I/O, lifecycle, and deferred-tool runtime behavior.
- Claude provider support lives under `Claude/`; follow `Claude/AGENTS.md` for `ClaudeAdapter`, Claude config, Claude provider setup, and Claude stream decoding.
- Claude HTTP hook listener, settings generation, and approval policy code lives under `Claude/Hooks/`; follow `Claude/Hooks/AGENTS.md` for that subsystem.
- Transcript grouping code lives under `Transcript/`; follow `Transcript/AGENTS.md` for `ChatItemGrouper` behavior.
- `ContextWindowCache` is app-level provider metadata, not conversation history. Keep it in the JSON-backed cache under Application Support, key entries by `providerID:model`, and treat it as advisory: provider-reported result data always wins. Cache writes should stay best-effort/background so turn completion and transcript persistence do not wait on disk I/O.

## Cross-Folder Debugging

- When investigating missing, duplicate, or stuck transcript rows, cross-reference the provider transcript (Claude JSONL today), runtime events, and SwiftData instead of trusting any single source:
    - **Start from the conversation.** Identify the `Conversation.id`, provider session ID, and canonical cwd so the matching provider transcript path is unambiguous.
    - **Compare raw and decoded events.** Check whether the provider transcript contains the expected raw records or hook attachments before assuming the adapter decoded or dropped them incorrectly.
    - **Inspect persisted rows.** Query `ConversationEventRecord`s for that conversation ordered by `timestamp` and primary key so event order, `type`, `toolId`, `toolName`, `stopReason`, and `toolApprovalStatus` can be compared against the raw transcript.
    - **Check live runtime state.** If the UI shows a pending approval or spinner, also check whether the manager still has a live process for the conversation; stale processes can explain prompts that render but do not resume.
    - **Keep scope here.** Document cross-source transcript debugging in this file; use `Alveary/Data/AGENTS.md` only for SwiftData model invariants or schema-level persistence contracts.
