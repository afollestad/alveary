## Data Models

These instructions cover the SwiftData models under `Alveary/Data/` — conversations, projects, transcript event records, session-scoped tool approvals, and the shared `ModelContext` helpers. Three feature clusters are nested and own their own rules: `Alveary/Data/Threads/AGENTS.md` for thread naming, identity, and picker state, plus `Alveary/Data/PullRequests/AGENTS.md` and `Alveary/Data/Scheduled/AGENTS.md`.

**Keep a rule here only when the code that would violate it is not the code that documents it.** Mechanism whose only reader is its own file belongs in a doc comment: `ModelContext+ToolApprovalResolution`'s nil-status question and `ConversationEventRecord.hostToolOutcomeType`'s column mapping each carry theirs.

### Persistence Invariants

These are persistence contracts backed by SwiftData fields. Treat them as hard constraints unless the work explicitly includes a coordinated migration.

- **Archived-thread restore uses persisted per-conversation `pendingRestoreContext`, not provider resume.** Regenerate the summary from saved `ConversationEventRecord`s, hydrate it into `ConversationState.stagedContext` when the view model is recreated, send it only through the staged-context path, and clear the field on dismissal or successful send.
    - **Restore summaries carry actionable conversation history only.** Exclude UI-only transcript notes such as session handoff markers, so recovery context does not tell a fresh provider session about Alveary display state.
- **Tool approval resolution belongs on the associated transcript row.** Store approve/deny state on the `tool_approval` `ConversationEventRecord` via `toolApprovalStatus`, not a separate model, so button state survives rebuilds and restarts.
- **Session-scoped tool approvals are the exception.** `AgentSessionApprovalRule` stores provider-scoped, session-scoped grants — exact Bash commands, command groups, exact file paths — that let `AgentCLIKit` answer future requests through Alveary's persistence adapter.
    - **`AgentSessionApprovalSelection` is not a grant**; it stores only the last approval-button pick, to preselect the next prompt.
    - **Keep both out of transcript persistence** — rendering still reads final button state from `ConversationEventRecord.toolApprovalStatus`.
    - **Rows are keyed by provider, conversation ID, and provider session ID**; remove them when that conversation's runtime session is replaced or destroyed.
- **`Project.remoteName` and `Project.gitRemote` are a paired invariant**: persist and update together, and have Git, worktree, and GitHub flows read the stored `remoteName` instead of rediscovering a remote.
- **Sidebar manual ordering uses optional dense order fields.**
    - `Project.sidebarSortOrder` is set only while `Project.isPinned == false`; pinned projects keep it `nil`.
    - `Project.pinnedSortOrder` and `AgentThread.pinnedSortOrder` share one dense order for visible pinned projects, standalone Project threads, and pinned Task threads.
    - Unpinned, archived, draft, and pinned-Project-nested threads keep `pinnedSortOrder == nil`; generic repair must not change a draft's unrelated `isPinned`.
    - Initialization and sidebar lifecycle changes renumber visible order fields dense to `0..<count`.

### Transcript Event Records

- **`ConversationEventRecord.type` and `.role` are persisted discriminators.** Use the model's `static let` constants (`messageType`, `toolCallType`, `toolApprovalType`, `userRole`, …), never a repeated literal — a typo silently stops matching rows instead of failing to build.
    - Test fixtures may keep literals; asserting the raw persisted value is what catches an accidental constant rename.
- **Token rows are append-only history.** Persist `tokenCacheCreation`, `providerModelId`, `contextWindowSize`, and `costUsd` on the reporting event, not a separate usage model.
    - **`context_window_invalidated` is a hidden boundary marker** inserted after a model change on a successful fork so old provider-reported maxes stop applying; it never renders in transcript or restore summary.
    - **Spend is not context usage.** Usage is latest-window state from the latest token row; spend sums token-row `costUsd` for the active conversation tab, including pre-compaction and pre-invalidation rows.
- **`sub_agent_completed` and `host_tool_outcome` reuse existing columns**, so neither needed a migration. The first stores the tool ID in `toolId` and metrics in `durationMs` plus JSON `content`, drives grouping only, and stays out of restore text.
    - **`ScheduledTaskProposalReceipt` cannot stand in for `host_tool_outcome`**: it is pruned by process token and retention window, so it is a dedup ledger, not history.

### Fetch Predicates

- **`ModelContext+Resolve.swift` hosts the shared typed lookups** such as `resolveThread(id:)`; prefer them over ad-hoc `model(for:) as?` casts, and add a sibling resolver when another model grows a second call site.
- **Keep `#Predicate` relationship keypaths one level deep.** A nested optional traversal such as `conversation.thread?.project?.path == projectPath` compiles, but the store cannot translate it and the fetch raises `NSInvalidArgumentException: Unsupported function expression TERNARY(...)` — an Objective-C exception `try?` cannot contain, so the app crashes.
    - **Predicate on the nearest relationship** and reach the far side through the model graph. When a route needs a to-many relationship per fetched row, set `FetchDescriptor.relationshipKeyPathsForPrefetching` so reads stay batched (`ContentView+DiffViewerRouting.swift`).
- **Bind the value to a local before comparing it in `#Predicate`** — `let recordType = ConversationEventRecord.toolApprovalType` above the fetch, never an inline literal. Each `#Predicate` expands into a nested generic `PredicateExpressions` tree that an inline literal must be resolved through, at steep type-check cost.
    - Cost also climbs with each `&&`. Declare a multi-term predicate once and reuse it (`DefaultClaudeApprovalPersistenceStore+Queries.swift` holds the session-approval shapes).

### Async Property Access

- **Do not read persisted `@Model` properties on a model reference across an `await`.** SwiftData can invalidate backing state during suspension; a post-await getter can trap with `_assertionFailure` and crash.
    - Snapshot the primitive values you need into locals before the await — value types survive the hop (`ThreadDetailView.removeConversation(id:conversationIDString:)` takes the pre-snapshotted string and captures `threadPersistentID` before awaiting teardown).
    - Re-resolve through the `ModelContext+Resolve.swift` helpers after the await before `.delete(_:)`, `.save()`, or any persisted-property read; treat a `nil` re-resolve as already removed, not an error.
- **Do not trust `modelContext.model(for:)` as a "safe to read" gate inside an async task, even before the first `await`.** It can return a non-nil zombie whose first persisted-property read traps synchronously, and a successful `as?` cast does not materialize the backing row.
    - Snapshot the persisted values where the model is known live — the `confirmationDialog` closure that just rendered `displayName()`, say — and pass IDs into the async helper. Never re-resolve a full `@Model` just to read a UUID or name.
