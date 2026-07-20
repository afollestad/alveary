## Composer Behavior

These instructions cover composer-specific view code under `Alveary/Views/Input/`.

> **READ FIRST — Focus and keyboard rules are centralized.** Before touching `@FocusState`, `.focusedSceneValue`, `.onKeyPress`, or `.keyboardShortcut` in this folder, consult the **Focus And Keyboard Coordination** section in `Alveary/Views/AGENTS.md`. The production AppKit body consumes first-responder request tokens through `BlockInputView.focusEditor()` and should not add another focus path.

## BlockInputKit Ownership

- Production composer editing is BlockInputKit-owned. Do not reimplement editor projection, completion UI, drops, undo, selection, IME behavior, copy/paste, or sizing behavior in Alveary.
- `AppKitChatComposerEditorController` owns Alveary's non-view BlockInput bridge: focus-token consumption, stop confirmation, preferred-height invalidation, and draft snapshot lifecycle. Editor fill, border, radius, and clipping belong to BlockInputKit style config.
- BlockInputKit owns editor visible-line height animation. Editor-driven surface relayout must be immediate so the editor and action-row bottoms stay fixed while the editor grows upward.
- Keep `BlockInputComposerCompletionProvider` identity stable across ordinary composer updates. BlockInputKit treats provider replacement as a semantic completion reset and dismisses the active popup.
- Keyboard behavior for Enter, Shift+Enter, Cmd+Enter, and Escape must use `BlockInputConfiguration.keyboardShortcuts`. Do not add composer key interception outside BlockInputKit APIs.
- Composer visible height must use BlockInputKit visible-line sizing. Keep Alveary-side layout as preferred-height invalidation only; do not reintroduce custom grow/shrink min/max-height logic.
- File and image drops are composer-panel owned. Keep BlockInputKit editor drops disabled in production, route picked/dropped URLs through Alveary staging, and render the attachment strip outside BlockInputKit so the editor never owns the top preview row.
- App-shot preview chips are host-owned composer attachments, but their AX tree and provider transport wrapper are hidden from the editor and transcript. Removing the preview should only unstage the app shot; it must not mutate composer Markdown.
- Slash-command argument hints are BlockInputKit inline hints backed by current local-command metadata or cached `Skill.argumentHint` values. Keep local hints live across model/provider refreshes without replacing the completion provider, and never insert hints as draft text.
- Composer selection background must stay visually distinct from composer chip fill; use a neutral non-accent token for selection chrome and keep chip fill/foreground tokens unchanged.

## Voice Input

- The app-local hold-to-dictate shortcut is the sole composer key-monitor exception: keep it on the mounted `AppKitChatComposerPanelView`, scoped to the visible supported composer in Alveary's key window, and synthesize a forced release when the monitor detaches or becomes invalid.
- Keep one stable weak editor handle across routine composer reconfiguration. Draft identity replacement and detach must synchronously stop/commit before clearing the old editor or document store.
- Dictation owns a BlockInputKit provisional-text transaction. Make the editor read-only while it is active, update only through its authorized token, finish with exactly one commit or a no-undo cancel, then synchronously call `flushDraftFromEditor()` before unlocking draft-mutating controls.
- Mouse, shortcut, and accessibility activation must share the coordinator reducer. UI controls own only event tracking, visual state, and temporary focus restoration.

## Drafts And Sending

- BlockInput Markdown is the sendable composer text. `ComposerDraft.messageText` returns the stored Markdown directly.
- Hot-path BlockInput mutations should update only cheap state such as effective emptiness and dirty revisions. Markdown serialization belongs in coalesced document-change publishing or explicit `flushDraftFromEditor()` calls before send/queue/steer flows.
- Programmatic app-owned draft replacements should go through `replaceInputDraft` / `clearInputDraft` so the bridge sees a revisioned external replacement without resetting selection for self-publishes.
- `ChatComposerTextSupport` is not an editor helper. Keep it limited to shared presentation labels, progress placeholders, effective-empty checks for string fallbacks, and legacy transcript `@` mention chip rendering.

## Composer Popovers

- Composer popup menus must reuse `AppKitComposerPopoverSurfaceView` and `AppKitComposerPopoverDividerView` from `Components/AppKit/` instead of hand-rolled popover surfaces or divider views.

## Worktree Picker

- The worktree-location picker is an empty-thread-only control for git-backed threads. New threads seed `AgentThread.useWorktree` from the global `createWorktreeByDefault` setting, the picker edits that per-thread override before first send, and it should disappear once `hasCompletedInitialSetup` flips true.
- Once hidden, do not surface redundant `"Local"` or `"Worktree (<last-path-component of worktreePath>)"` text in the composer action row; the sidebar owns committed worktree indication.

## Composer Action Row

- Keep renderer-neutral decisions in `ComposerPresentation` and caller-owned option lists.
- Keep presentation pure: compute labels, disabled states, placeholders, action copy, busy return behavior, effort options, and trust blocking from caller-owned inputs.
- Keep effects elsewhere: no draft mutation, persistence, settings writes, tasks, or service calls in presentation types.
- Keep the `+` menu presentation-only inside `ChatComposerActionRowView`. File picking, BlockInputKit insertion, and plan-mode mutation must remain callbacks owned by the composer panel or view model.
- Task Workspace controls are mode-specific composer settings, not attachments. The native action row presents current grants, `AppKitChatComposerPanelView` owns the directory picker, and `ConversationViewModel` owns validation/persistence/reconfiguration.
- Provider and model options are caller-owned inputs populated from `AgentProviderDiscoveryService`; the action row renders them but must not discover providers, refresh models, or read provider config directly.
- Reasoning controls are caller-owned inputs.
  - Render effort as the oversized snapping slider.
  - Render models as an inline disclosure list, grouped by provider only when multiple non-empty groups are present.
  - Resize the inline model list and popover immediately when disclosure changes; do not animate the list expansion. Keep the rotating caret treatment and pinned controls.
  - Render Fast as a separate toggle only when supported: use `bolt` with enablement help while off and accent-tinted `bolt.fill` with disablement help while on.
  - Keep the compact reasoning button's active-only indicator as accent-tinted `bolt.fill`, preserving its compact sizing and spacing.
- `/fast` is an Alveary local command. Keep it enable-only: `/fast` selects Fast, `/fast <prompt>` selects Fast and sends or queues that prompt with a next-turn required speed. Do not add a special inline argument hint for it.
- `/effort` is a model-scoped Alveary local command. Enable, reserve, suggest, and intercept it only while the selected model advertises effort options; preserve provider order and join every canonical value with `|` in its inline hint.
  - Bare `/effort` clears only the command text, preserves attachments, sends nothing, does not request editor focus, and opens the existing reasoning popover.
  - `/effort <value>` accepts exactly one case-insensitive canonical option through the existing effort-change callback. Clear and refocus only when accepted; otherwise retain the draft and attachments and surface the current dynamic options or the underlying setting error.
- `ChatComposerActionRow` owns the bottom settings/action row; `ChatComposerActionRowView` owns native AppKit rendering inside the production panel.
- The leading `+` button must remain square to the dropdown height, with default, hover, pressed, focused, and disabled states clipped to the same circular background.
- Native controls that custom-draw dynamic `NSColor`s must resolve colors through `appKitRenderingAppearance` and invalidate display from `viewDidChangeEffectiveAppearance()`.
- `ComposerMode.ProgressReason.canStop` is the single source of truth for whether the action slot renders a stop button and whether Escape stop confirmation is armed.
- Tool-specific waiting copy for deferred tools must flow through the `ComposerMode.ProgressReason.toolApproval(...)` payload, not through new `toolName` switches.
- The action row height is 30pt, matching `.regular` `ProminentActionButtonStyle`. Keep native primary/stop button heights, disabled send footprint, and progress slots in lockstep so the composer does not shift vertically.
- Stop confirmation lives inside the stop button label. The first Escape arms `isStopConfirmationArmed` and expands the button to `Confirm`; timeout or any state where `canUseEscapeToStop == false` must clear it.

## Staged Context

- Queued-message edit, rollback, send, steer, and session-handoff draft flows must preserve `stagedContext` unless the user explicitly dismisses it.
- Native queued-message rows render queued text as Markdown with the composer inline-code palette and legacy `@` mention chips. This keeps BlockInput Markdown links/images visible while preserving old stored mention rendering.
