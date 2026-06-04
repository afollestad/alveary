## Data Models

These instructions cover the SwiftData models under `Alveary/Data/`.

- Thread and main-conversation naming rules:
    - **Store the visible thread label on `AgentThread.name`, manual-rename state on `hasCustomName`.** `hasCustomName` distinguishes a deliberate rename from the default untitled state and must be set to `true` by any manual rename flow.
    - **Only auto-name a thread while it is effectively untitled.** The gate is `!hasCustomName && trimmedName == "New thread"` — a thread that has been manually renamed must never be overwritten by the auto-namer.
    - **Auto-title a conversation whenever `customTitle == nil`, independently of the thread.** The first user message may set `Conversation.title` even if the thread already has a non-default name.
    - **Cascade a thread rename into the main conversation's `title` when the user hasn't explicitly diverged it.** The predicate lives at `Conversation.shouldFollowThreadRename(previousThreadDisplayName:)` and fires either when `customTitle == nil` *or* when the conversation's visible `displayName()` still matches the thread's previous `displayName()`. The second clause is what keeps repeated thread renames in sync after the first cascade has populated the conversation's title.
    - **Do not add a separate rename affordance for the sole conversation when only one exists.** The thread rename cascade covers it.
    - **Read the main conversation's default display name from `Conversation.defaultDisplayName()`, which returns `AgentThread.untitledName` (`"New thread"`).** Do not hard-code `"Main"` as a fallback in rendering or comparison code.

## Persistence Invariants

These are persistence contracts backed by SwiftData fields. Treat them as hard constraints unless the work explicitly includes a coordinated migration.

- Archived-thread restore uses persisted per-conversation `pendingRestoreContext`, not provider resume. Restoring a thread should regenerate that summary from saved `ConversationEventRecord`s, hydrate it back into `ConversationState.stagedContext` when the conversation view model is recreated, send it only through the existing staged-context path on the next outbound message, and clear the persisted field when the user dismisses it or that send succeeds.
- Tool approval resolution belongs on the associated transcript row:
    - **Use the existing row.** Store approve/deny state on the `tool_approval` `ConversationEventRecord` via `toolApprovalStatus`.
    - **Do not add a separate model.** Keeping status on the transcript row preserves the associated button state across rebuilds and app restarts.
- Session-scoped tool approvals are the exception:
    - **Use `AgentSessionApprovalRule` for hook-owned session grants.** This model stores provider-scoped, session-scoped approval rules such as exact Bash commands, Bash command groups, or exact file paths.
    - **Use `AgentSessionApprovalSelection` for the remembered split-button choice.** This model stores only the last per-session approval-button selection (`Approve once`, exact session, or group session); it is not itself an approval grant.
    - **Do not mix these into transcript persistence.** Session approval rules let `AgentCLIKit` answer future Claude approval requests for the same Claude session through Alveary's persistence adapter, while session approval selections only preselect the next permission prompt. Transcript rendering still reads the final button state from `ConversationEventRecord.toolApprovalStatus`.
    - **Keep lifecycle bounded by conversation and provider session.** These rows are keyed by provider, conversation ID, and Claude `sessionId`, and should be removed when that conversation's runtime session is replaced or destroyed.
- `Project.remoteName` and `Project.gitRemote` are a paired invariant. Persist and update them together, and have Git/worktree/GitHub flows use the stored `remoteName` instead of rediscovering a remote ad hoc.
- `AgentThread.model` is the per-thread model override. It mirrors the `permissionMode`/`effort` pattern for thread-scoped picker state, but with a different nil semantic:
    - **Store `nil` for "use the provider's default model".** The composer picker's `"default"` value is a UI sentinel that `applyModelChange` translates to `nil` before persisting — never write the literal string `"default"` into `AgentThread.model`, or the adapter will pass `--model=default` to the CLI.
    - **Seed from `AppSettings.defaultModel` at thread creation.** `SidebarViewModel.createThread` reads the app-wide default and maps `"default"`/empty values back to `nil` on the new `AgentThread`. Preserve non-empty model strings because live provider model metadata can change independently of app releases.
    - **Read the live DB field in bindings, not a transient state mirror.** `ChatView.selectedModelBinding` must read `conversation.thread?.model` so the picker reflects the persisted value across view-model re-inits and session forks; do not reintroduce a parallel `ConversationState.selectedModel` cache.
- Context-window metadata is persisted on `ConversationEventRecord` token rows:
    - **Keep token rows append-only conversation history.** Persist `tokenCacheCreation`, `providerModelId`, `contextWindowSize`, and `costUsd` on the token event that reported them instead of adding a separate conversation usage model.
    - **Use `context_window_invalidated` only as a hidden boundary marker.** Model changes after a successful session fork insert this record so old provider-reported max sizes stop applying, but the marker must not render in the transcript or restore summary.
    - **Do not treat spend like context usage.** Context usage is latest-window state from the latest token row; total spend is the sum of token-row `costUsd` for the active conversation tab, including rows before compaction or context-window invalidation.
- `AgentThread.effort` is model-scoped, not universal. Both the set of acceptable values *and* the preferred default depend on which model the thread is using.
    - **Read per-model efforts from `AgentModelOption`.** `AgentModelOption.supportedEffortOptions` and `defaultEffortOption` from `AgentProviderDiscoveryService` are the source of truth for settings and composer controls. Do not add app-owned effort maps in `AppSettings`; it should only trim/fallback empty persisted strings.
    - **Coerce in lockstep with model changes.** `ConversationViewModel.applyModelChange` receives the selected model's effort options from `ConversationView`, and `SettingsViewModel.defaultModel` resolves them from refreshed provider status. Reset unsupported values to the model option default in the same save as the model write so SwiftUI sees model + effort invalidate on one render tick and only **one** `reconfigureSession()` fork fires.
    - **Seed new threads from Settings.** `SidebarViewModel` reads the already-normalized Settings effort when creating a thread; Settings owns applying model-option defaults when the user changes the default model.
    - **Filter the composer dropdown before rendering.** `ConversationView` derives effort menu options from the selected `AgentModelOption` and passes them into `ChatView`/`ChatComposerActionRow`; action-row presentation must not rediscover providers or consult app-owned effort maps.

## Model Context Helpers

- `ModelContext+Resolve.swift` hosts shared typed lookup helpers such as `resolveThread(id:)`. Call sites should prefer `modelContext.resolveThread(id:)` over ad-hoc `modelContext.model(for: id) as? AgentThread` casts so the cast lives in one place. Add sibling resolvers here when another model grows a second call site.
- Fetch-backed resolvers (`resolveThread` / `resolveConversation` / `resolveProject`) are the safe choice after an `await`. `modelContext.model(for:)` can return a non-nil zombie whose next persisted-property read traps; the fetch helpers materialize only still-live rows and return `nil` otherwise.

## Async Property Access

- **Do not read persisted `@Model` properties on a model reference across an `await`.** SwiftData can refresh or invalidate the model's backing state during suspension; a post-await getter (e.g. `Conversation.id`, `AgentThread.worktreePath`) can then trap with `_assertionFailure` and crash the app.
    - **Snapshot primitive property values into locals before the await.** Capture the `String`, `Int`, `Bool`, `URL`, etc. you need, then use the locals across the suspension — they are value types and survive the hop. `ThreadDetailView.removeConversation(id:conversationIDString:)` receives `conversationIDString` as a parameter (snapshotted by the caller) and captures `threadPersistentID` before awaiting runtime teardown.
    - **Re-resolve through the fetch-backed helpers in `ModelContext+Resolve.swift` after the await** before calling `.delete(_:)`, `.save()`, or reading any other persisted property on it. Treat a `nil` re-resolve as "someone else already removed it" rather than surfacing an error — the user's intent is satisfied.
    - **Why:** `modelContext.model(for:)` can still hand back a non-nil zombie after suspension. The fetch-backed helpers only return still-live rows, which is what async cleanup flows actually need.

- **Do not trust `modelContext.model(for: persistentIdentifier)` as a "this model is safe to read" gate inside an async task.** `model(for:)` can return a non-nil zombie reference whose backing store has been invalidated — the first persisted-property read on that zombie (e.g. `.id`, `.name`) traps with `_assertionFailure` synchronously, before any `await`. A successful `as?` cast does not materialize the backing row.
    - **Snapshot the persisted-property values you need at the call site where the model is known to be live.** For the conversation-delete flow that means the `confirmationDialog` button closure, where SwiftUI just rendered `conversation.displayName()` on the same synchronous frame: capture `conversation.persistentModelID` *and* `conversation.id` there and pass both into the async helper. The helper then uses the pre-captured String across its own pre-await control flow instead of re-fetching a `Conversation` reference and reading `.id` on it.
    - **How to apply:** when a SwiftUI modal/confirmation is the entry point to an async delete/move/reconfigure flow, design the async helper to accept the persisted IDs it needs as parameters. Do not re-resolve the full `@Model` inside the helper just to read a UUID or name — that's the shape that introduced the zombie-reference trap. Re-resolve is still correct post-await for the operations that actually need a live model (`.delete(_:)`, `.save()`, cascade reads).
    - **Why:** this second crash hit `Conversation.id.getter` in `removeConversation` *before* the `destroyRuntime` await — the post-await fix in the first rule didn't help, because the trap was inside `let conversationIDString = dbConversation.id` itself. The helper was re-fetching a model reference the caller already had, and that re-fetch returned a zombie.
