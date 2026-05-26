## Chat View Details

These instructions cover chat-specific view code under `Alveary/Views/Chat/`. Narrower scopes:

- Transcript shell and approval plumbing → `Transcript/AGENTS.md`.
- Transcript scrolling and follow-mode → `Transcript/Scrolling/AGENTS.md`.
- Transcript markdown-link resolution → `Transcript/Links/AGENTS.md`.
- Conversation tab row (chip rendering, rename, shortcuts, scroll hooks, sentinel, divider) → `ConversationTabs/AGENTS.md`.
- Transcript block primitives → `Blocks/AGENTS.md`.
- Tool, approval, prompt, and task block rules → `Blocks/*/AGENTS.md`.

> **READ FIRST — Focus and keyboard rules are centralized.** Before touching `@FocusState`, `.onKeyPress`, or `.keyboardShortcut` on any chat surface, consult the **Focus And Keyboard Coordination** section in `Alveary/Views/AGENTS.md`.

## Transcript And Composer Rendering

- `AppKitChatSurfaceView` owns the active chat surface's parent layout.
  `ChatView` may still build SwiftUI content-mode child views, but the vertical
  transcript/empty-state/composer frame split belongs to the AppKit surface.
- Mostly-vertical wheel events over nested horizontal scroll views, such as
  markdown tables and code blocks, should route directly to the vertical
  transcript scroll owner from the chat surface. Do not send those events to the
  horizontal child first; replaying them upward loses AppKit scroll momentum.
- `AppKitChatComposerPanelView` owns the composer panel shell:
    - **Keep shell chrome native.** Transparent outer background, horizontal
      padding, top-content vertical offset, top divider, and panel measurement
      belong there.
    - **Own production top content.** Last-turn errors, session-continuity
      notices, and staged-context banners render through native AppKit top
      content in the production panel so their height and hit testing share the
      editor/action-row coordinate space.
    - **Own production action-row placement.** Active `ChatView` routes
      `ChatComposerActionRowView` through the AppKit panel so editor/action-row
      spacing is measured natively.
    - **Own production queued-message placement.** Active `ChatView` routes
      pending queued messages through `AppKitChatQueuedMessagesView` above the
      native composer body. Do not let production queued rows re-enter a
      SwiftUI editor stack.
    - **Own production composer body.** Active `ChatView` configures
      `AppKitChatComposerBodyView` for the BlockInputKit editor bridge,
      preferred-height invalidation, and shortcut configuration. Production
      fixes should stay on the native body path.
- `ProjectTrustPromptView` lives in `ProjectTrustPrompt.swift`; `ThreadDetailView+ProjectTrust.swift` owns the trust-state checks and denial deletion.
- `EmptyThreadState` lives in `ChatView+EmptyThreadState.swift` and checks `isCancellingInitialSetup` before `setupPhase` so cancellation feedback takes precedence even when `setupPhase` is still set mid-rollback. Keep that ordering if you restructure the view; otherwise the empty-thread pane flickers back to "Creating worktree" during the rollback shell commands.
- Transcript rendering is AppKit-owned. Keep live transcript row work under `Blocks/AppKit/` and route it through `Transcript/Scrolling/AppKitTranscriptRowFactory.swift`; do not reintroduce SwiftUI transcript row views.
- User transcript bubbles still render as markdown, including slash-command and `@`-mention chips. AppKit rows reuse `AppMarkdownParser.attachComposerChips(to:)` and `ChatComposerTextSupport.composerTextChips(in:)`; chip labels are always `lastPathComponent`, so bubble rendering does not need a working directory.
- Long static user and assistant bubbles should keep exact AppKit markdown measurement for frame/clipping/fade controls. Keep Show more/less on the AppKit header toggle; do not add bubble-wide gestures or nested vertical scroll views.
- `attachComposerChips(to:)` skips any attributed-string range that already carries a markdown `.link`, a `.codeBlock` block-level `presentationIntent` (fenced code block), or a `.code` `inlinePresentationIntent` (backtick inline code). The inline-code guard is load-bearing: `composerTextChips` is invoked with the *parsed* flat string (backticks stripped), so the helper's own `codeRanges`-based filter returns nothing to exclude. Without the guard, a user writing `` `@path/to/file.swift` `` would have their inline code clobbered by a composer chip that truncates the path to `@file.swift`. Keep each condition; each covers a distinct case.
- Composer top separators that appear while the transcript is scrolled up should be the composer panel's own top overlay, not a parent overlay or a child inside the background fill. Keeping the divider overlaid avoids clipping when vertical panel padding is small.
- Composer panel top/bottom clearance should have one owner per edge. Production editor-to-action-row spacing comes from `AppKitChatComposerPanelView.Layout.actionRowSpacing`; do not stack that padding with native panel spacing.
- Native staged-context banner production rendering lives in `AppKitChatComposerTopContentView`. Keep staged context above the composer without introducing transcript rows.
- Do not reintroduce a changed-files strip above the composer. Diff status belongs in the main toolbar button that opens the Diff Viewer, so changed-file loading cannot alter transcript/composer height or leave stale transcript measurements.

## Interaction Contracts

These capture conversation-view interaction patterns. Keep new UI aligned with them unless intentionally redesigning.

### Presentation Contracts

- **Share contracts.** Route content-mode, composer-mode, and thread-setting display decisions through `ChatPresentation` / `ChatThreadPresentation`.
- **Keep presentation pure.** Presentation types may read caller-owned state and compute labels/modes, but must not own runtime state, start tasks, save models, or call services.
- **Avoid branch drift.** SwiftUI hosts and native AppKit views should consume the same contracts instead of duplicating branching.
- **Preserve visuals during native migration.** AppKit replacements must match the SwiftUI surface they replace for sizing, spacing, typography, colors, disabled treatment, hover, and pressed states unless the change is explicitly approved as a redesign.

### Conversation Behavior

- `ThreadDetailView` should fetch live conversations for the selected thread before sorting/rendering tabs. Do not sort `thread.conversations` directly in its render path; stale relationship entries can trap when SwiftUI refreshes after a conversation delete.
- `ThreadDetailView` must observe `.agentStatusChanged` for the current thread's conversation IDs and invalidate itself when one fires. The tab row reads `agentsManager.status(for:)` synchronously during render; without an explicit invalidation, a selected conversation tab can miss busy/idle/error transitions until some unrelated view state happens to re-render the header. Keep that invalidation token threaded into `ThreadDetailConversationTabs` as an explicit input (`statusVersion` today) rather than hiding it in a closure-side effect — the tabs need a real view input dependency so SwiftUI re-evaluates the selected chip immediately.
- `ThreadDetailView` owns the Claude project-trust gate for new threads. Keep trust-state checks and denial deletion in `ThreadDetailView+ProjectTrust.swift`, and pass a plain disabled flag down to composer surfaces instead of letting input controls read Claude config directly.
- Session reconfiguration is a between-turn action. Agent/session setting changes must not reconfigure a conversation while a turn is active or a send is in flight; they wait until the current turn finishes.
- Context-window summary derivation belongs in `ConversationUsageSummary`, not in composer controls. Keep the split semantics intact: the latest token row drives current token usage, the latest post-invalidation reported `contextWindowSize` wins over cache, cached max only seeds the UI when no reported max is available, and total spend sums token rows for the active conversation only.
- Composer-dropdown `apply*Change` handlers live on `ConversationViewModel` in `ConversationViewModel+Settings.swift`. The three fork-triggering handlers (`applyModelChange` / `applyEffortChange` / `applyPermissionModeChange`) run their state/DB write synchronously and return a `@discardableResult Task<Void, Never>` carrying the async fork; `applyWorktreePreferenceChange` is a plain `Void`-returning DB write (no fork, only editable before first send). Rules:
    - **Do not inline the handler logic back into `ChatView`.** The view-model home is what makes them unit-testable against a `MockAgentsManager`; `ConversationViewModelTests+Settings.swift` depends on that entry point.
    - **Call the handlers directly from `Picker` `set:`.** No outer `Task { await ... }` wrapper. The sync prologue must run on the same cycle as the click so SwiftUI's next render observes the new value; an outer `Task` defers it one MainActor cycle and briefly paints the stale selection.
    - **Every handler must start with `guard canApplySettingsChange else { return ... }`.** Rejects writes while `turnState.isActive`, `isSendingMessage`, or a tool approval is pending. The composer's `.disabled(areControlsDisabled)` is UI-level; this is defense-in-depth against stray binding writes (programmatic, races on mode flips).
    - **Do *not* gate the fork on `agentsManager.isRunning(conversationId:)`.** Claude's `-p --input-format stream-json` process can exit between turns, so `isRunning` silently drops the fork. `reconfigureSession` already handles a dead process (no-op teardown, then `--resume <id> --fork-session` spawn). Gate through `shouldReconfigureOnSettingChange()` — "thread completed initial setup" — which is the real precondition.
    - **Do *not* add a `!isReconfiguringSession` check at the handler layer.** Concurrent fork attempts are handled inside `reconfigureSession` (`!state.isReconfiguringSession` silently returns), and the composer enters `.progressOnly(.reconfiguringSession)` which disables the pickers while a fork is in flight.
- Queued messages stay stacked above the composer until actually sent. Don't render pending queued entries in the transcript as if they were already history.
- Once a queued message is actually attempted, it belongs to the transcript. If that attempted send fails, show retry affordances on the transcript user message rather than moving it back into the queue.
- `AskUserQuestion` answers and deferred tool approvals share one conversation-scoped interaction lane:
    - **Prioritize the question.** If an unanswered prompt is on screen, keep the prompt submit path available and reject tool approval actions until the question is answered.
    - **Supersede stale approvals after the answer sends.** If a deferred tool approval was pending from the same turn, answering the prompt should mark that approval row `superseded` instead of resuming Claude through the old approval path.
    - **Keep normal composer sends blocked.** The transcript prompt is the only allowed outbound action while the question is pending; do not reopen normal freeform sending or setting changes.
- User-requested turn cancellation is an interruption, not a generic failure. Stopped turns clear composer error banners, render a centered `Interrupted` transcript note, and persist a `stop` session note so restore/archive context doesn't summarize the turn as an error.
- Session handoff is a between-turn hidden flow.
    - **Hide the handoff exchange.** The handoff prompt/response must not render as transcript rows; after the fresh provider session starts, append only the centered `Session handoff` lifecycle note.
    - **Keep handoff context ahead of queues.** Staged, edited, and immediate handoff output must use the handoff send path so it seeds the fresh session before any queued messages resume.
    - **Keep failures blocking.** Failed hidden handoffs stay in a blocking retry state so later visible sends cannot continue from provider-only context.
    - **Keep steering automatic-only.** Handoff steering is prompted only for automatic handoffs. Manual handoff commands and retries go straight to the hidden handoff flow, reusing any already-submitted steering after a failure.
    - **Keep countdowns independent.** `handoffSteeringCountdownSeconds` controls only the user's steering prompt. `handoffPromptSendCountdownSeconds` controls only generated handoff output sending, and `0s` means send the generated output immediately without staging it in the composer.
    - **Keep steering app-owned.** User steering must be appended through `SessionHandoffPromptBuilder`, not through the customizable default prompt. The hidden prompt receives the non-customizable steering contract, and the fresh-session seed appends raw steering under `## User Prompt`.
    - **Preserve interrupted drafts.** When automatic handoff temporarily takes over a non-empty composer draft, restore that draft after the handoff seed message sends successfully, and restore it on hidden handoff failure.
- Other subtle runtime lifecycle cues should use the same centered-note transcript treatment instead of inventing new bubble styles. Claude plan-mode transitions belong on that centered-note path, including `Entered plan mode`, `Exited plan mode`, and denied `ExitPlanMode` as `Staying in plan mode`, not in standalone tool pills.
- First sends are durable transcript attempts once accepted:
    - **Persist before setup.** `deliverMessageReserved` inserts the user row before initial setup starts.
    - **Keep failures on the transcript.** Setup/spawn/send failures mark that row retryable instead of returning to a centered empty retry state.
    - **Treat cancellation as reset.** `ConversationViewModel.cancel()` cancels `initialSetupTask`, restores draft/staged context, deletes the attempted row, and clears `hasCompletedInitialSetup`. `sendDraft` swallows `CancellationError`.
- While a turn is active, keep transcript updates incremental. Persisted live-turn events append directly into `ChatItemGrouper`; full transcript regrouping from the `events` query is deferred until the turn ends so the active turn doesn't starve composer interactions like autocomplete or text insertion.
- Live root-assistant `messageChunk` events are coalesced before hopping onto the main actor. Do not process every streamed text delta as its own `MainActor` mutation, or active turns can starve transcript completion and composer interactions.
- `ConversationViewModel` agent subscriptions are view-lifecycle owned, not initializer-owned. Keep `activateViewLifecycle()` / `deactivateViewLifecycle()` wired from `ConversationView`'s `.task` and `.onDisappear` instead of restarting subscriptions from `init`, because parent SwiftUI refreshes can recreate the model and churn `activeSubscriptionToken`.
