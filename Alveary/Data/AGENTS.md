## Data Models

These instructions cover the SwiftData models under `Alveary/Data/`.

- Thread and main-conversation naming rules:
    - **Store the visible thread label on `AgentThread.name`, manual-rename state on `hasCustomName`.** Every manual rename flow sets `hasCustomName = true`.
    - **Provider metadata is the automatic main title source.** It applies the normalized `name ?? preview` title (provider `name` beats `preview`) to `AgentThread.name` while `hasCustomName == false`. Keep `hasCustomName` false for provider-generated labels, and never overwrite a manual rename.
    - **Do not locally auto-title the main conversation or thread from the first user message.** The main conversation follows provider metadata through the rename cascade below; Alveary keeps no second durable title source for the main flow.
    - **Use `AgentSessionPreviewGenerator.preview(fromInitialPrompt:)` for local preview-only needs** — secondary conversation auto-titles and pre-launch worktree slugs, falling back to the current thread name for slugs.
    - **Cascade a thread rename into the main conversation's `title` when the user hasn't diverged it.** `Conversation.shouldFollowThreadRename(previousThreadDisplayName:)` fires when `customTitle == nil` *or* when the conversation's visible `displayName()` still matches the thread's previous one — the second clause keeps repeated renames in sync after the first cascade populates the title.
    - **No separate rename affordance for a sole conversation**; the cascade covers it.
    - **Read the main conversation's default display name from `Conversation.defaultDisplayName()`** (`AgentThread.untitledName`, `"New thread"`); never hard-code `"Main"`.

## Persistence Invariants

These are persistence contracts backed by SwiftData fields. Treat them as hard constraints unless the work explicitly includes a coordinated migration.

- `AgentThread.isDraft` marks the one process-local provisional new-thread row; its stored default stays `false` so pre-field stores migrate existing threads as real. Drafts own one persisted main conversation but no provider session, runtime, worktree, branch, setup completion, or visible events.
- `AgentThread.modeRawValue` is the persisted Project-versus-Task identity, defaulting old stores to Project. Never derive mode from `project != nil`: a Task's `project` is sidebar placement only — its workspace and source-project paths live in the flat fields plus `taskWorkspaceDescriptor`, and project deletion detaches Task children instead of cascading into their history.
- Archived-thread restore uses persisted per-conversation `pendingRestoreContext`, not provider resume. Regenerate the summary from saved `ConversationEventRecord`s, hydrate it into `ConversationState.stagedContext` when the view model is recreated, send it only through the staged-context path on the next outbound message, and clear the field on dismissal or successful send.
- Restore summaries carry actionable conversation history only — exclude UI-only transcript notes such as session handoff markers, so recovery context does not tell a fresh provider session about Alveary display state.
- Tool approval resolution belongs on the associated transcript row: store approve/deny state on the `tool_approval` `ConversationEventRecord` via `toolApprovalStatus`, not a separate model, so button state survives rebuilds and restarts.
- Session-scoped tool approvals are the exception:
    - **`AgentSessionApprovalRule`** stores provider-scoped, session-scoped grants (exact Bash commands, command groups, exact file paths) that let `AgentCLIKit` answer future requests through Alveary's persistence adapter.
    - **`AgentSessionApprovalSelection`** stores only the last per-session approval-button pick (`Approve once`, exact session, group session) to preselect the next prompt; it is not a grant.
    - **Do not mix these into transcript persistence** — rendering still reads final button state from `ConversationEventRecord.toolApprovalStatus`.
    - Rows are keyed by provider, conversation ID, and provider session ID; remove them when that conversation's runtime session is replaced or destroyed.
- `Project.remoteName` and `Project.gitRemote` are a paired invariant: persist and update together, and have Git/worktree/GitHub flows use the stored `remoteName` instead of rediscovering a remote.
- Sidebar manual ordering uses optional dense order fields:
    - `Project.sidebarSortOrder` is set only while `Project.isPinned == false`; pinned projects keep it `nil`.
    - `Project.pinnedSortOrder` and `AgentThread.pinnedSortOrder` share one dense order for visible pinned projects, standalone Project threads, and pinned Task threads.
    - Unpinned, archived, draft, and threads nested under a pinned Project keep `pinnedSortOrder == nil`; generic repair must not change a draft's unrelated `isPinned`.
    - Initialization and sidebar lifecycle changes renumber visible order fields dense to `0..<count`.

### Thread Picker State

- `AgentThread.model` is the per-thread model override, mirroring the `permissionMode`/`effort` picker pattern with a different nil semantic:
    - **`nil` means "provider default".** The dropdown's `"default"` value is a UI sentinel translated to `nil` before persisting — writing the literal makes the adapter pass `--model=default` to the CLI.
    - **Seed from `AppSettings.defaultModel` at thread creation** (`SidebarViewModel.createThread` maps `"default"`/empty to `nil`); preserve non-empty strings, since live provider model metadata changes independently of app releases.
    - **Build composer reasoning state from the live DB field.** `ConversationView.composerReasoningSelection` reads `conversation.thread?.model` so the dropdown survives view-model re-inits and forks; no parallel `ConversationState.selectedModel` cache.
- Context-window metadata persists on `ConversationEventRecord` token rows:
    - Token rows are append-only history; persist `tokenCacheCreation`, `providerModelId`, `contextWindowSize`, and `costUsd` on the reporting event, not a separate usage model.
    - `context_window_invalidated` is a hidden boundary marker inserted after a model change on a successful fork so old provider-reported maxes stop applying; it never renders in transcript or restore summary.
    - Spend is not context usage: usage is latest-window state from the latest token row; spend sums token-row `costUsd` for the active conversation tab, including pre-compaction/pre-invalidation rows.
- Sub-agent completion markers are hidden `ConversationEventRecord` rows: `sub_agent_completed` stores the tool ID in `toolId` and metrics in `durationMs` plus JSON `content` (no migration), drives grouping only, and stays out of restore text.
- A pending review submission is a JSON envelope on `Conversation` (`pullRequestReviewProposalJSON`), not a model: one per conversation, cascading with it, and needing no container registration. `Services/PullRequests/AGENTS.md` owns its rules. Its sibling `pullRequestHostToolReceiptsJSON` is the pull request tools' retry ledger; both follow the optional/no-`init` contract above.
- Host MCP widget outcomes are hidden `ConversationEventRecord` rows too: `host_tool_outcome` stores the host tool name in `toolName`, the feature's correlation key (a proposal id) in `toolId`, and its payload in `content` — existing columns, no migration. `ScheduledTaskProposalReceipt` cannot serve this purpose: it is pruned by process token and retention window, so it is a dedup ledger, not history.
- `AgentThread.effort` is model-scoped — acceptable values *and* the preferred default depend on the thread's model:
    - **`AgentModelOption.supportedEffortOptions` / `defaultEffortOption`** from `AgentProviderDiscoveryService` are the source of truth; no app-owned effort maps in `AppSettings`, which only trims/falls back empty persisted strings.
    - **Coerce in lockstep with model changes.** Reset unsupported values to the model-option default in the same save as the model write, so SwiftUI sees model + effort invalidate on one render tick and only **one** `reconfigureSession()` fork fires (`ConversationViewModel.applyModelChange`, `SettingsViewModel.defaultModel`).
    - **Seed new threads from Settings**, which owns applying model-option defaults when the default model changes.
    - **Filter the composer dropdown before rendering.** `ConversationView` derives effort options from the selected `AgentModelOption` and passes them down; action-row presentation must not rediscover providers.
- `AgentThread.speedMode` is optional thread-scoped speed state. Normalize `nil`/empty/unknown to `AgentSpeedMode.standard`; persist `.fast` only when provider status reports speed support, and coerce stale Fast back to Standard in the same save as provider/model normalization.

### Linked Pull Requests

- `AgentThread.linkedPullRequestsJSON` and `Project.linkedPullRequestsJSON` hold linked pull requests as a JSON envelope, bridged by `linkedPullRequests` in the `+PullRequestLinks.swift` companions through the shared `LinkedPullRequestStorage` codec so the two columns cannot drift. They are columns rather than a child `@Model` because that would add a relationship every `ModelContainer` must register (one production site, ~43 test containers). `PullRequestLinkOwner` (thread or project, by `PersistentIdentifier`) plus `ModelContext.linkedPullRequests(for:)` / `setLinkedPullRequests(_:for:)` address a link's owner without per-model branching.
    - **Reverse lookups fetch then decode.** `PullRequestLinkedOwnerLookup` answers "which owners link pull request X" for the pane's linked-owners section; `#Predicate` cannot see into the JSON, so its descriptors only narrow to `linkedPullRequestsJSON != nil` rows and the pure matcher filters those. Keep new reverse queries on that shape rather than promoting links to a relationship.
    - **Keep both columns optional with no `init` parameter.** `nil` migrates pre-field stores, and the `AgentThread.init` omission keeps `makeForkThread` from carrying links onto a fork, which gets its own branch and therefore its own pull requests.
    - **The stored `PullRequestSummary` is a refetchable cache, not truth** — it lets the toolbar glyph render without a network round trip; the pane prefers fresh `PullRequestDetail` and refreshes the snapshot on open.
    - **Decode failure yields an empty list** (a malformed blob must not make its owner unopenable); setting an empty list clears the column to `nil`, never `[]`.
    - **Nothing enforces uniqueness across owners** — the same pull request may be linked from several threads or projects; only per-owner duplicates are rejected, by the link store.
- `AgentThread.pendingPullRequestPromptsJSON` and `pullRequestScanWatermark` back transcript link detection (see `Alveary/ViewModels/Conversation/AGENTS.md`). Both follow the optional/no-`init` contract above, so a fork inherits neither open questions nor its source's scan fence.
    - **The watermark advances only for a message that yielded identifiers**, so ordinary traffic does not dirty the thread row; a message at or before it never prompts again, fencing replays.
    - **A message naming more than `ConversationViewModel.maximumDetectedPullRequestsPerMessage` pull requests prompts for none of them**, and auto-links none either. It is enumerating them — a `list_involved_prs` answer runs to dozens — not discussing one, and every identifier would otherwise stack its own question under the bubble. The watermark still advances: the message was scanned and deliberately produced nothing.
    - **A prompt is keyed by anchoring message, not just pull request** — `messageEventID` is the `ConversationEventRecord.id` that is also the message's `ChatItem.id`, so the row survives relaunch and full rebuilds under the same bubble.
- Scheduled-task persistence separates mutable definitions from immutable run provenance:
    - **Keep recurrence structured.** `ScheduledTask` persists flat recurrence fields plus a pinned IANA timezone; use its `recurrence` bridge, never RRULE text.
    - **Snapshot before execution.** `ScheduledTaskRun.init(snapshotting:...)` makes revision, prompt, provider settings, project path, grants, occurrence identity, and claimed directory identities durable across edits and definition deletion. Missing or malformed identity provenance fails closed for execution and recovery.
    - **Decode persisted run state exactly in safety gates.** Use `decodedStatus` and `hasKnownTerminalStatus`; the `status` bridge's `.failure` fallback is presentation compatibility, not proof an unknown raw value is terminal. Unknown nonterminal status, trigger, or workspace provenance blocks execution/resume and is interrupted during recovery; known terminal status stays authoritative history.
    - **Scope crash recovery for terminal interactions.** Set `ScheduledTaskRun.requiresFinalizationRecovery` in the same save as executor-owned terminal state; clear it durably only after interaction cleanup and verified runtime suspension. Startup may supersede terminal-run approvals/questions only while the marker is set.
    - **Preserve history with nullification.** Project deletion nullifies schedules, schedule deletion nullifies runs, Task-thread deletion nullifies run provenance; existing Project-thread and conversation cascades stay unchanged.
    - **Mutate future work only.** Definition mutations are revision-checked; pause/resume/edit clear `pendingOccurrenceAt` and recompute `nextOccurrenceAt` strictly after the action time. Never rewrite an active run snapshot. Project deletion pauses and detaches definitions without changing run Task workspaces.
    - **Retain failed owned-workspace cleanup provenance** — original source path and directory identity, worktree path, branch, and ownership-record identity — until marker-verified filesystem *and* Git cleanup both complete. On private-workspace cleanup failure, keep the descriptor plus prepared root/strategy/marker on the Task shell so permanent deletion can retry.
    - **Workspace-less scheduled Task shells are deletion-safe only when terminal.** Reject deletion when prepared-workspace or pending-cleanup fields are ambiguous/incomplete. A sanitized shell may derive an ownership-only cleanup descriptor from validated prepared metadata but must not re-expose changed Project or grant roots.
    - **Keep natural-language proposals noncanonical.** `ScheduledTaskProposal` is one pending, conversation-owned confirmation snapshot: cascade with its source conversation, nullify its trusted Project, fail closed on unknown payload versions/actions, and revision-check definitions again at confirmation. Persist positive `enqueueOrdinal` values for FIFO ties (legacy nil/nonpositive rows sort first by date and ID). Persist the host-tool response receipt on `Conversation` in the same save that opens a proposal so an exact retry cannot reopen it; creating or mutating a definition consumes its proposal in the same save, and Run now uses the proposal ID as its durable occurrence idempotency key.

## Model Context Helpers

- `ModelContext+Resolve.swift` hosts shared typed lookups such as `resolveThread(id:)`; prefer them over ad-hoc `model(for:) as?` casts, and add sibling resolvers when another model grows a second call site.
- `ModelContext+ToolApprovalResolution.swift` owns whether a `tool_approval` row with no `toolApprovalStatus` is still actionable. A `nil` status only means nobody answered — the provider can run the tool or end the turn without Alveary stamping the row — so transcript restore and the sidebar's waiting dot both ask here rather than reading the column directly.
- Fetch-backed resolvers (`resolveThread` / `resolveConversation` / `resolveProject`) are the safe choice after an `await`: `modelContext.model(for:)` can return a non-nil zombie whose next persisted-property read traps, while the fetch helpers materialize only still-live rows and return `nil` otherwise.
- `ConversationEventRecord.type` and `.role` are persisted discriminators. Use the `static let` constants on the model (`messageType`, `toolCallType`, `toolApprovalType`, `userRole`, …), never a repeated literal — a typo silently stops matching rows instead of failing to build. Test fixtures may keep literals; asserting the raw persisted value is what catches an accidental constant rename.

## Fetch Predicates

- **Keep `#Predicate` relationship keypaths one level deep.** A nested optional traversal such as `conversation.thread?.project?.path == projectPath` compiles, but the store cannot translate it and the fetch raises `NSInvalidArgumentException: Unsupported function expression TERNARY(...)` — an Objective-C exception `try?` does not contain, so the app crashes. Predicate on the nearest relationship and reach the far side through the model graph. When a route needs a to-many relationship per fetched row, set `FetchDescriptor.relationshipKeyPathsForPrefetching` so reads stay batched (`ContentView+DiffViewerRouting.swift`).
- **Bind the value to a local before comparing it in `#Predicate`** — `let recordType = ConversationEventRecord.toolApprovalType` above the fetch, never an inline literal. Each `#Predicate` expands into a nested generic `PredicateExpressions` tree, and an inline literal must be resolved through it instead of arriving as a plain `String`; hoisting one literal made the difference between the app's most expensive CI expression and a trivial one.
    - Cost also climbs with each `&&`. Declare a multi-term predicate once and reuse it (`DefaultClaudeApprovalPersistenceStore+Queries.swift` holds the session-approval shapes). The type-check budget catches regressions only on CI, so give new multi-term predicates a shared descriptor from the start.

## Async Property Access

- **Do not read persisted `@Model` properties on a model reference across an `await`.** SwiftData can invalidate backing state during suspension; a post-await getter can trap with `_assertionFailure` and crash.
    - Snapshot the primitive values you need into locals before the await — value types survive the hop (`ThreadDetailView.removeConversation(id:conversationIDString:)` takes the pre-snapshotted string and captures `threadPersistentID` before awaiting teardown).
    - Re-resolve through the `ModelContext+Resolve.swift` helpers after the await before `.delete(_:)`, `.save()`, or any persisted-property read; treat a `nil` re-resolve as already removed, not an error.
- **Do not trust `modelContext.model(for:)` as a "safe to read" gate inside an async task, even before the first `await`.** It can return a non-nil zombie whose first persisted-property read traps synchronously, and a successful `as?` cast does not materialize the backing row — this crash hit `Conversation.id.getter` *before* the teardown await, because the helper re-fetched a model the caller already had.
    - Snapshot the persisted values at the call site where the model is known live (e.g. the `confirmationDialog` button closure that just rendered `displayName()`), pass IDs into the async helper as parameters, and never re-resolve a full `@Model` just to read a UUID or name. Re-resolve remains correct post-await for operations that need a live model.
