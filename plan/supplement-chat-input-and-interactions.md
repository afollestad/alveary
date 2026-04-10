# Supplement: Chat Input and Interactions

`ChatInputField`, autocomplete, queueing UI, steering, scroll behavior, and composer performance. Continues from [Part 4d: Chat Blocks and Tool Rendering](part4d-chat-blocks.md).

Implementation progress:
- [x] `ChatInputField` now uses selection-aware text editing for `@` file autocomplete and `/skill` autocomplete, including async source loading, debounced filtering, popup-local selection state, and keyboard navigation.
- [x] Drag-and-drop file insertion is wired into the composer, and outbound draft sends now strip `@` prefixes before delivery while preserving relative project paths where possible.
- [x] Snapshot coverage includes the queue-only busy composer state plus representative file and skill autocomplete popup presentations.

### Chat Input Field

The base composer lands with the Chat View Architecture step in Phase 6. The richer input affordances in this section (`@` file autocomplete, `/skill` autocomplete, drag-and-drop attachment) are layered on in the later **Input and Message Handling** step so the build order stays incremental.

Phase split: during the earlier Chat View Architecture step, implement the editable composer shell, busy/queue/stop behavior, and dropdown bindings. During the later **Input and Message Handling** step, add autocomplete popups, popup-local state, and drag-and-drop.

Ownership split: [Part 4c](part4c-chat.md) is the source of truth for where the composer sits in the chat stack, while the [Composer State and Live Progress supplement](supplement-composer-and-live-progress.md) owns the runtime state matrix (`idle` vs busy vs reconfiguring vs initial setup) and setting-change wiring. This section owns the `ChatInputField` component API and its local behaviors (text editing, autocomplete, drag-and-drop, popup state). Keep that split so queue/steer/stop semantics do not drift across two plan sections.

```swift
struct ChatInputField: View {  // Skep/Views/Input/ChatInputField.swift
    @Binding var text: String
    let mode: ComposerMode
    let onSubmit: () -> Void
    let onSteer: () -> Void
    var onStop: (() -> Void)?
    @Binding var selectedModel: String
    @Binding var selectedEffort: String
    @Binding var selectedPermissionMode: String
    var supportedPermissionModes: [PermissionModeOption]
    var supportedEffortLevels: [String]
    var supportsMidTurnSteering: Bool
    var loadFileCompletions: () async -> [String]
    var loadSkillCompletions: () async -> [Skill]
}
```

The key contract points from that signature are documented in the prose below rather than in per-line comments: `mode` is the render-only composer-state boundary, `text`/`selectedModel` are launch-scoped bindings, effort/permission mode bind to persisted thread state, and the completion loaders remain owner-supplied async boundaries.

State ownership is intentionally split. Durable per-conversation composer state for the current app session lives outside the view: `text` binds to `ConversationState.inputDraft`, `selectedModel` binds to `ConversationState.selectedModel`, and effort/permission mode bind to persisted thread properties. In v1, `selectedModel` is intentionally a **launch-scoped override** rather than persisted thread metadata: it survives navigation/reconfigure within the current launch but resets on archive, `kill()`, and app relaunch, unlike persisted `effort` / `permissionMode`. When the conversation is stopped, the owner-provided binding setters apply those changes for the next spawn only; when a session is already running, those same setters route through the optimistic-with-revert helper from the [Composer State and Live Progress supplement](supplement-composer-and-live-progress.md) so the visible control keeps matching the actual live session instead of drifting ahead optimistically. For persisted thread fields, that helper also saves through the active `ModelContext` before attempting `reconfigureSession()`. `ConversationState` is still in-memory service state rather than SwiftData, so app relaunch / archive / `kill()` recreate it instead of restoring old drafts or queued messages. Ephemeral input-only UI — the active autocomplete trigger/range, filtered popup results, highlighted suggestion row, drag-hover state, and any temporary inline preview bookkeeping — stays local `@State` inside `ChatInputField`. That local UI survives ordinary re-renders while the same conversation view stays mounted, but resets when the selected conversation changes or the chat view is torn down. File-path suggestions intentionally use an **on-demand async provider** instead of a long-lived `[String]` snapshot: when the `@` popup opens (or the working directory changes), the composer asks `FileListManager` for the latest list so invalidation from diff/chat refreshes actually reaches the popup. Slash-command suggestions use the same boundary: the owner provides `loadSkillCompletions()` so the composer never reaches into `SkillsService` or a `Resolver` directly.

Provider capability metadata follows the same boundary. `ChatInputField` does **not** resolve provider data on its own; it receives `supportedPermissionModes`, `supportedEffortLevels`, and `supportsMidTurnSteering` as plain values from the owner-supplied `ComposerCapabilities` snapshot described in [Part 4c](part4c-chat.md). Empty arrays hide unsupported dropdowns, and `supportsMidTurnSteering == false` removes the busy-state steer shortcut/affordance without requiring Claude-specific branches in the view.

Keyboard focus follows the same split. The text editor is the normal first responder for chat composition, so Enter/Shift+Enter/Option+Enter route through `ChatInputField` only while the composer is focused. Autocomplete popups are composer-local overlays and dismiss when focus leaves the input. `mode` is also the correctness boundary for the primary action chrome: `ChatInputField` should not try to reconstruct the documented progress-only states from a disabled parent view and two booleans.

The input field at the bottom of the chat area:

- **Multiline**: the field grows vertically as the user types, up to a max height (~6 lines), then scrolls internally. **Enter submits** in `.idle` / `.busy(...)` modes (send when idle, queue when busy). `.progressOnly(...)` has no submit path. **Option+Enter** inserts a newline.
- **Inline markdown preview**: deferred in v1. The composer stays plain text while editing; markdown/code styling appears after send in the chat history. This keeps the highest-frequency typing path free of per-keystroke attributed-text mutation. The validated macOS 26 `TextEditor(Binding<AttributedString>)` path remains a future enhancement if users need live formatting later.
- **@-mention autocomplete**: typing `@` triggers a fuzzy-matched file path popup sourced from `FileListManager`. The popup appears anchored above the input field:

```
│  ┌─────────────────────────────────────────────┐  │
│  │  src/auth.swift                             │  │
│  │  src/auth.test.swift                        │  │
│  │  src/login.swift                     3 of 8 │  │
│  └─────────────────────────────────────────────┘  │
│  ┌─────────────────────────────────────────────┐  │
│  │ Fix the bug in @src/auth                    │  │
│  └─────────────────────────────────────────────┘  │
```

  - Opening the popup triggers `loadFileCompletions()` so the suggestion source is re-read from `FileListManager` after any invalidation.
  - Results filter as the user types after `@` (fuzzy match against `git ls-files` output).
  - `loadFileCompletions()` is called once per popup session (or working-directory change), then subsequent keystrokes filter that in-memory array instead of re-running `git ls-files`.
  - Fuzzy filtering runs in a cancellable task with a small debounce (~75ms) and caps the rendered list to the best 50 matches so very large repos do not hitch the main thread on every keystroke.
  - **↑/↓** navigate the list; **Enter** or **Tab** confirms the selection (inserts the full path); **Escape** dismisses without selecting.
  - The popup shows a match count ("3 of 8") and scrolls if there are many results.
  - The selected file path is inserted as-is — the agent reads files with its own tools.

- **`/skill` autocomplete**: typing `/` at the start of the input triggers a popup listing available slash commands for the active conversation. Opening the popup triggers `loadSkillCompletions()` once for that popup session. The owner-supplied loader can prefer the latest `system/init` `slash_commands` metadata for the active conversation and fall back to `SkillsService.loadInstalled()` before the first spawn, without baking either dependency into `ChatInputField`. Same keyboard navigation as `@-mention`. Selecting a skill inserts `/skill-name` into the input.

- **File and image attachment via drag-and-drop**: dropping files onto the chat input area inserts their paths as @-mentions. Works for any file type — the agent reads them via its tools.
- **State while busy**: when `mode == .busy(canStop: true)`, the field shows steering/queueing guidance (for example, `"Send a message to steer, or queue for next turn..."`) and remains editable. If `supportsMidTurnSteering == false`, omit the steer-specific shortcut copy and present that busy state as queue-only. During the shorter `mode == .busy(canStop: false)` transition window (for example, respawn/send preflight), do **not** imply steering is available — show queue/progress-only guidance and a compact progress affordance instead of a misleading stop control. The Send button is replaced by a **Stop button** (■ icon) only when the associated `canStop` value is `true` and a live turn is actually running. Pressing Stop sends SIGINT as a cancellation request only; the field stays in its busy state until the stream reports turn completion or EOF cleanup.
- **Progress-only states**: when `mode == .progressOnly(...)`, keep the composer visible so the user can see their preserved draft and the normal control layout, but disable editing and replace the primary action area with a non-interactive progress affordance. This is how the documented initial-setup and fork-session reconfigure states are rendered; they are not modeled as a generic disabled idle composer.

### @-Mention File References

Typing `@` in the input triggers a fuzzy-matched file path popup (from `FileListManager`). The `@` prefix is stripped before sending -- paths within the project are sent as relative, paths outside as absolute. Each result row shows a file type icon, bold filename with highlighted matching characters, and muted directory path. Files dragged onto the input area are inserted as @-mention paths (same format as manual @-mentions).

`FileListManager` runs `git ls-files` and caches per project. Cache refreshes after each agent turn, after explicit local diff-viewer git mutations such as stage/unstage/discard, and on manual refresh. FSEvents refresh the diff summary only — they do **not** invalidate the `git ls-files` cache on every callback. Because the composer resolves completions on demand, those invalidations take effect on the next `@` popup open instead of leaving the UI stuck on an older array captured before the refresh. During a single popup session, the already-loaded source array is filtered locally in a debounced, cancellable task and the visible results are capped, so large repositories do not trigger repeated full-array scoring and rendering on every keystroke. The popup dismisses on Escape, selection, or cursor moving away. Arrow keys navigate; Enter selects.

### /Skill Autocomplete

Typing `/` at the start of the input triggers a skill autocomplete popup. Each row shows the skill name (bold, highlighted) and one-line description. Data source: the owner-provided `loadSkillCompletions()` boundary, which prefers the active conversation's latest `system/init` `slash_commands` when available and falls back to installed skills before the first spawn. Selecting inserts `/skill-name` into the input.

### Message Queuing UI

Queued messages appear **inside the chat scroll area** as dimmed user bubbles with a "Queued" label and ✕ dismiss button. They sit below the live working area. If a queued entry captured staged context from the input banner, the bubble also shows a small 📎 indicator so the user can see that extra context is attached even though the live banner has already been consumed. After a successful turn completion, the head entry is attempted automatically; it remains dimmed and queued until that send succeeds, then transitions to the full-opacity "You" style. If that auto-send fails, keep the head bubble in place and show a Retry action on that head only; later composer sends append behind it instead of bypassing it. While the head entry is already committed to the auto-send path (`ConversationState.inFlightQueuedMessageID`), its dismiss button is disabled so the user cannot remove a message that is already being written to stdin. If the user dismisses the only queued entry that owns staged context, that context returns to the live input banner instead of being silently discarded. The uncommitted changes list is pinned to the input bar (not the scroll area) and is sourced from the shared `DiffViewerViewModel.files` summary. Backed by `MessageQueue` and `TurnState`.

### Steering (Mid-Turn Guidance)

Steering sends a message mid-turn to redirect the agent (distinct from queuing, which waits for the next turn). The message is written as a JSON event to stdin while the agent is processing (verified by testing). Claude finishes the in-flight tool call, reads the steering message, and redirects.

**UI**: In v1, Enter queues after the current turn, Shift+Enter steers immediately, and `Option+Enter` inserts a newline without sending. This is a Claude-only path in the current plan. The registry still exposes `supportsMidTurnSteering` as future capability metadata, but non-steering providers are deferred until the plan defines a concrete owner for interrupt-and-next-turn fallback ordering; `ChatInputField` and `ConversationViewModel.steer()` do not implement that generic fallback in v1.

### Scroll Behavior

Auto-scroll during streaming, paused when the user scrolls up. A "Jump to bottom" floating pill appears when scrolled up and new content is arriving. The `isFollowing` flag (see `ChatView` in Part 4c) controls this -- set to `false` on scroll-up, `true` on pill tap or new turn start.

### Performance

- **`LazyVStack`** ensures only visible messages are rendered.
- **`@Query`** with SwiftData provides efficient, reactive data loading.
- **Live events** are appended to SwiftData as they arrive; SwiftUI's `@Query` automatically picks up new records.
- **@-mention search** filters a single popup-session snapshot in memory, with a small debounce/cancellation boundary and top-N cap, instead of rescanning/re-rendering the full repo-sized result set on every keystroke.
- For very long conversations, consider pagination (load most recent N events, load more on scroll-up).

**Snapshot tests:** cover all chat views, components, input bar states, and secondary screens with standard visual permutations. Non-obvious:
- `ChatView`: scrolled up with "Jump to bottom" pill visible (agent busy, `isFollowing = false`)
- `ChatView`: conversation with queued messages below working area
- `ChatView`: queued message carrying staged context (📎 indicator visible after the input banner has cleared)
- `ChatView`: queued head already committed to auto-send renders its dismiss control disabled
- `ChatView`: stalled queued head shows Retry, and later queued entries remain behind it rather than leaping ahead
- `ChatView`: inline banner stack permutations, including last-turn error, reconfigure-progress, session-continuity warning, permission banner, and staged-context banner in the documented order
- `EmptyThreadState`: untouched "Let's build" hero, both setup phases (`.creatingWorktree` / `.startingAgent`), and setup-failed retry state with the preserved draft visible in the composer
- `SubAgentBlock`: mixed agent types (header without type name), mixed running/complete with live status lines
- `ChatInputField`: @-mention autocomplete popup, /skill autocomplete popup, drag-and-drop file insertion, and the short outbound-reserved transition state (queue UI visible, stop hidden/replaced by progress)
- Conversation tabs: single conversation (no tab bar shown)
- Thread creation: setup in progress (spinner, input disabled) and setup failed (error with "Retry")
- GitHub auth modal: waiting state ("Waiting for authorization..." spinner)
