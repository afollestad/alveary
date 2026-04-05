# Supplement: Composer State and Live Progress

Composer state, setting-change wiring, streaming text, input-bar states, event grouping, and live progress. Continues from [Part 4c: Chat View](part4c-chat.md).

### Composer State Matrix

This matrix is the quickest way to reason about which controls are interactive in each composer state.

`ChatInputField` should receive these states explicitly as a small render-only enum instead of inferring them from a disabled wrapper around `isBusy`/`canStop`:

```swift
enum ComposerMode: Sendable {  // Skep/Views/Input/ComposerMode.swift
    case idle
    case busy(canStop: Bool)
    case progressOnly(ProgressReason)

    enum ProgressReason: Sendable {
        case initialSetup
        case reconfiguringSession
    }
}
```

| State | Text editor | Primary action area | Enter | Dropdowns |
|---|---|---|---|---|
| Idle (`mode == .idle`) | Enabled | Send button | Sends immediately | Enabled |
| Busy, live turn active (`mode == .busy(canStop: true)`) | Enabled | Queue + Stop | Queues | Disabled |
| Busy, outbound reserved / pre-turn preflight (`mode == .busy(canStop: false)`) | Enabled | Queue + compact progress affordance | Queues | Disabled |
| Fork-session reconfigure (`mode == .progressOnly(.reconfiguringSession)`) | Disabled | Progress-only; no send/queue/steer | No submit path | Disabled |
| Initial setup before first history (`mode == .progressOnly(.initialSetup)`) | Disabled | Progress-only | No submit path | Disabled |

`Shift+Enter` is only a steering shortcut while the conversation is busy **and** the provider supports mid-turn steering. It is not a separate idle-mode send path.

### Composer Wiring

The full `ChatInputField` call site carries a few non-obvious bindings that should be documented explicitly rather than hidden in comments:

- `composerCapabilities` is the chat subtree's only provider-specific input. `ConversationView` derives it once from `ProviderRegistry`, then `ChatView` uses it for the permission banner and passes the relevant pieces down to `ChatInputField`. That keeps the shared provider-driven UI compatible with future non-Claude providers without turning the chat subtree into a service locator.
- `selectedModel` binds to **launch-scoped** `ConversationState.selectedModel` using `"default"` as the UI sentinel for `nil`. That value survives navigation and reconfigure within the current launch, but it is not persisted thread metadata.
- `selectedEffort` and `selectedPermissionMode` bind to persisted thread fields, but their setters should route through the same optimistic-with-revert helper rather than mutating `conversation.thread` directly. When the session is stopped, that helper saves the new persisted value and stops there. When the session is running, it saves first, then performs the reconfigure flow from Parts 2f and 2h so the control never advertises a value the live session failed to adopt.
- `writeEscalationEligibleTools` stays alongside `suggestedWriteEscalationMode` inside `composerCapabilities` so the permission banner can suppress ineffective escalation CTAs after denied Bash / prompt tools.
- `loadFileCompletions` and `loadSkillCompletions` stay owner-supplied async boundaries. The composer requests fresh data when a popup opens instead of holding its own long-lived service reference or stale snapshot.

Focused wiring example:

```swift
ChatInputField(
    text: Bindable(viewModel.state).inputDraft,
    mode: composerMode,
    onSubmit: { ... },
    onSteer: { ... },
    onStop: { ... },
    selectedModel: Binding(
        get: { viewModel.state.selectedModel ?? "default" },
        set: { newValue in applyModelChange(newValue) }
    ),
    selectedEffort: Binding(
        get: { conversation.thread?.effort ?? "medium" },
        set: { newValue in applyEffortChange(newValue) }
    ),
    selectedPermissionMode: Binding(
        get: { conversation.thread?.permissionMode ?? "default" },
        set: { newValue in applyPermissionModeChange(newValue) }
    ),
    supportedPermissionModes: composerCapabilities.supportedPermissionModes,
    supportedEffortLevels: composerCapabilities.supportedEffortLevels,
    supportsMidTurnSteering: composerCapabilities.supportsMidTurnSteering,
    loadFileCompletions: loadFileCompletions,
    loadSkillCompletions: loadSkillCompletions
)
```

`ChatView` computes `composerMode` in one place so the documented progress-only states remain distinct from the queue-capable busy states. Use the pre-history UI invariant here, not `needsSetup` alone: the preserved-worktree retry path can still be in `.progressOnly(.initialSetup)` while `needsSetup == false`.

`applyModelChange`, `applyEffortChange`, and `applyPermissionModeChange` all follow the same contract: persist or update the visible setting first, reconfigure only when a session is currently running, and restore the previous visible value if the fork-session handoff fails. `applyPermissionModeChange` has one extra UI-state responsibility: once a permission-mode change is actually committed (stopped-session save or successful running-session reconfigure), clear `showPermissionBanner` and `lastPermissionDeniedToolNames` so the composer no longer advertises a denial against the old mode. If the running-session reconfigure rolls back, restore both the old mode value and the prior banner state.

Implementation note: do not open-code three separate optimistic/revert paths. Keep one small private helper in the owning chat layer, for example `applySessionSettingChange(...)`, that accepts closures for snapshot/apply/revert plus an optional running-session reconfigure action. For persisted thread fields, that helper must re-resolve/save through the active `ModelContext` before any running-session reconfigure so the stored metadata and live-session handoff stay in lockstep. That keeps busy gating, failure rollback, and "only reconfigure when a session is currently running" behavior shared without introducing a new protocol for what is still one local UI concern.

**Unit tests for `applySessionSettingChange(...)`:** cover stopped-session updates (no reconfigure call), running-session success, and running-session failure rollback for both launch-scoped model storage and persisted thread-backed storage. For permission mode specifically, assert that a committed change clears the permission banner state and a rollback restores it. This is the smallest place to guard the optimistic-with-revert contract without snapshot-testing every dropdown permutation.

### StreamingBubble

The `StreamingBubble` renders the in-progress assistant response as **plain text** (no markdown). It uses the same visual container as `AssistantBubble` but with a plain `Text` view instead of Textual's richer markdown rendering, plus a blinking cursor indicator at the end:

```swift
struct StreamingBubble: View {  // Skep/Views/Input/StreamingBubble.swift
    let text: String
    @State private var cursorVisible = true

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text(text)
                .textSelection(.enabled)
            Rectangle()
                .fill(.primary.opacity(cursorVisible ? 0.6 : 0))
                .frame(width: 2, height: 16)
                .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true), value: cursorVisible)
        }
        .onAppear { cursorVisible = false }  // Triggers the repeating animation
    }
}
```

When the full `assistant` event arrives, `streamingText` is set to `nil`, the `StreamingBubble` disappears, and the complete message appears as an `AssistantBubble` with full markdown rendering (code blocks, syntax highlighting, lists, links, etc.). If the turn ends without a finalized assistant message (for example cancellation, permission denial, or another terminal error), the terminal `.tokens` event also clears `streamingText` so the UI does not leave a stale plain-text bubble hanging under the new banners/history. EOF cleanup remains the last-resort fallback if the process exits before either terminal event path arrives.

### Input Bar States

The input bar at the bottom of the chat view changes based on the agent's state:

**Idle (ready for input):**
```
┌─────────────────────────────────────────────────────────┐
│ Ask anything, @ to add files, / for skills              │
├─────────────────────────────────────────────────────────┤
│  🔷 Opus ▾   ⚡ High ▾   🔒 Default ▾           ⬆    │
└─────────────────────────────────────────────────────────┘
```

- Multiline `TextEditor` with placeholder text.
- Below the input, a toolbar row of compact controls: `Menu` dropdowns for model, effort (conditional), and permission mode, and the send button on the far right. The **model dropdown** is a single combined control showing the current model with the provider icon (e.g. "🔷 Opus ▾"). It opens a menu listing available models: "Default" (uses the CLI's default), "Opus", "Sonnet", "Haiku". Since Claude is the only provider in v1, no separate provider picker is needed — the provider icon is decorative. When additional providers are added, this dropdown can be split or show a grouped menu (provider → model). The selected model is conversation-scoped (`ConversationState.selectedModel`) and is passed to the CLI via `--model` at spawn time only when non-default. If the conversation is stopped, changing it just updates that in-memory override for the next spawn; changing it on a running session calls `agentsManager.reconfigureSession()` which kills the process and re-spawns with `--fork-session` to preserve context (same mechanism as effort and permission mode changes). If that running-session reconfigure fails, restore the previous dropdown value so the control keeps representing the actual live session instead of only the next attempted spawn. The **effort dropdown** (e.g. "⚡ High ▾") is only visible when the current provider's `supportedEffortLevels` is non-nil. New threads seed `AgentThread.effort` from `AppSettings.effort`; the dropdown then reads/writes that persisted thread value, which is passed to the CLI via `--effort` at spawn time. If the conversation is stopped, the persisted value is simply used on the next spawn; changing it on a running session calls `agentsManager.reconfigureSession()` which kills the process and re-spawns with `--fork-session` to preserve context. On running-session failure, restore the previous persisted value so the badge and dropdown stay aligned with the still-live session. The **permission mode dropdown** is driven by the active provider's `supportedPermissionModes` metadata and is hidden when the provider exposes no permission-mode support. For Claude in v1, that metadata yields Default, Plan, Auto-Edit, Auto, and Auto-Approve, mapping to `default`, `plan`, `acceptEdits`, `auto`, and `bypassPermissions`. The intentionally CI-focused `dontAsk` mode is simply omitted from Claude's provider metadata, so the shared UI does not need a Claude-specific exclusion branch. New threads seed `AgentThread.permissionMode` from `AppSettings.permissionMode`; the dropdown reads/writes that persisted thread value. If the conversation is stopped, changing the mode just updates the persisted thread value for the next spawn; changing it on a running session triggers `reconfigureSession()` with `--fork-session`, and failure restores the previous persisted mode so the visible badge still matches the actual runtime. **All three dropdowns are disabled while `turnState.isActive`, `state.isSendingMessage`, or `state.isReconfiguringSession`** — mid-turn or mid-send changes would target work already in flight, and reconfigure-in-flight changes would target a disappearing process. During reconfigure, the composer shows the inline "Applying session changes..." banner and temporarily disables submit / queue / steer until the replacement session is ready.
- Send button is enabled when text is non-empty. `Enter` submits while idle; `Option+Enter` inserts a newline.
- `@` triggers file autocomplete, `/` triggers skill autocomplete (see the [Chat Input and Interactions supplement](supplement-chat-input-and-interactions.md), **@-Mention File References** and **/Skill Autocomplete**).

**Busy (agent working):**
```
┌─────────────────────────────────────────────────────────┐
│ Send a message to steer, or queue for next turn...      │
├─────────────────────────────────────────────────────────┤
│  🔷 Opus ▾   ⚡ High ▾   🔒 Default ▾   Queue   ■    │
└─────────────────────────────────────────────────────────┘
```

- Placeholder changes to indicate steering/queueing options (for example, `"Send a message to steer, or queue for next turn..."`).
- While a live turn is active, the send button becomes a **Stop button** (■) that sends SIGINT. This is a cancellation request, not an immediate UI-state flip — the composer stays busy until the stream reports `.tokens` or the process actually exits. During the shorter outbound-reserved-but-not-yet-streaming window, show the same busy/queueing chrome but replace Stop with a compact progress affordance so the UI does not imply that SIGINT is already meaningful.
- A **Queue** button appears — pressing it (or Enter) queues the message for after the current turn. If a staged-context banner is visible, queueing captures that context onto the queued entry and clears the input banner immediately because the "next message" has already claimed it.
- `Shift+Enter` sends as a steering message (immediate, mid-turn) for Claude in v1. `Option+Enter` still inserts a newline.

**Progress-only (initial setup or reconfigure):**

- The composer still renders its full chrome, but the text editor and dropdowns are disabled and the primary action area is replaced with a non-interactive progress affordance.
- `.progressOnly(.initialSetup)` is the pre-history owner for both the brand-new worktree path and the preserved-worktree retry path while `setupPhase` is active.
- `.progressOnly(.reconfiguringSession)` keeps the existing draft visible but temporarily blocks send/queue/steer until the fork-session handoff finishes.

**With queued messages:**
```
┌─────────────────────────────────────────────────────────┐
│ ┌─────────────────────────────────────────────────┐     │
│ │ "Also add unit tests for the auth module"    🗑  │     │
│ ├─────────────────────────────────────────────────┤     │
│ │ "Make sure to run the linter"                🗑  │     │
│ └─────────────────────────────────────────────────┘     │
│                                                         │
│ Type another message...                                 │
├─────────────────────────────────────────────────────────┤
│  🔷 Opus ▾   ⚡ High ▾   🔒 Default ▾   Queue   ■    │
└─────────────────────────────────────────────────────────┘
```

- Queued messages appear as dimmed user bubbles at the bottom of the chat scroll area, just above the input region, each with a dismiss button.
- If a queued entry captured staged context, its queued bubble shows a small 📎 indicator so the user can still tell that extra context will be included even though the input banner has already cleared.
- If the queued head is already committed to the auto-send path, its dismiss button is disabled until that send either succeeds or fails.
- Messages are shown in queue order (first to send first).
- After a successful turn completion (`.tokens` without error or permission denial), the next queued message is attempted automatically. The entry remains visible in the queued state until that send succeeds, then transitions into a full "You" bubble in the chat history.

Auto-follow and the "Jump to bottom" pill should target a dedicated bottom anchor after the queued-message region, not the last `ChatItem` ID. The visual tail of the scroll view can be the streaming bubble or queued bubbles even when no new persisted event has been appended yet.

### Event Grouping

`ChatItem`, `ToolEntry`, `SubAgentEntry`, and `ChatItemGrouper` (all in `Skep/Services/Agent/ChatItemGrouper.swift`) drive the chat rendering. The Chat View reads `viewModel.state.grouper.items` for rendering.

**Performance note**: every `modelContext.save()` triggers a `@Query` re-evaluation. During busy tool-use turns this can mean dozens of saves per second. Mitigations:
- **Incremental grouping** via `ChatItemGrouper` (`Skep/Services/Agent/ChatItemGrouper.swift`).
- **Adaptive batch saves**: coalesced via `scheduleSave()` (~350ms while busy, ~150ms when idle).
- **`LazyVStack`**: only visible rows are rendered.
- **Dedicated bottom anchor**: follow-mode scrolls to the actual end of the scroll content, so queued-bubble inserts and streaming updates do not leave the viewport one item behind.
- **Conditional `.transaction`**: disables animations on the `ScrollView` only while `turnState.isActive` to suppress layout thrashing from `@Query` updates during streaming — re-enables when idle so `DisclosureGroup` animations work normally.

### Live Progress (While Agent Is Working)

While the agent is processing a turn (events streaming in), the chat view shows a **live working area** at the bottom of the conversation, above the input field:

```
┌─ Claude is working... ─────────────────────┐
│                                             │
│  ● Reading `src/auth.ts`               3s  │
│  ✓ Read `src/login.ts`                      │
│  ✓ Bash  `git log --oneline -5`             │
│    └ a1b2c3d Fix auth bug                   │
│                                             │
│  ◉ Thinking...                              │
│                                             │
└─────────────────────────────────────────────┘
```

- **Current tool** shows with a pulsing ● indicator and an elapsed time counter.
- **Completed tools** show with a ✓ and their summary. If the tool has output, a brief **inline result annotation** appears beneath the tool entry (last line of `output`, truncated to ~80 chars, muted style with a `└` connector). This gives quick context without requiring expansion.
- **Thinking** shows as a pulsing indicator (optionally expandable to see the thinking text as it streams).
- **Overflow**: when the tool list exceeds 3 visible items, older completed tools collapse into a "+N more tool uses" summary (clickable to expand). Only the current tool and last 2 completed tools remain visible. This prevents the live area from growing unbounded during long multi-tool turns.
- A **Stop button** replaces the Send button in the input area while the agent is busy. It sends SIGINT to request cancellation, but the live working area remains visible until the stream reaches `.tokens` or EOF cleanup.
- Once the turn completes, this live area collapses into a static **working block** in the message history (see [Part 4d](part4d-chat-blocks.md)).
- When the top-level agent transitions from tool use to generating a text response, `messageChunk(parentToolUseId: nil)` events begin arriving. These accumulate into `viewModel.streamingText`, which the `StreamingBubble` renders as plain text with a blinking cursor (see **StreamingBubble** above). Chunks tagged with a sub-agent `parentToolUseId` are ignored by the top-level bubble; the durable sub-agent UI waits for the full inner `assistant` event/tool history. When the full top-level `assistant` event arrives, the `StreamingBubble` disappears and is replaced by an `AssistantBubble` with full markdown rendering.

This live area is driven directly by the `ConversationEvent` stream -- each `toolCall` event adds a line, each `toolResult` marks it complete, `thinking` events update the thinking indicator, and top-level `messageChunk` events progressively build the streaming response bubble.

Working blocks, tool rendering (Read, Edit, Write), sub-agent blocks, task list blocks, and prompt blocks are in [Part 4d: Chat Blocks and Tool Rendering](part4d-chat-blocks.md).
