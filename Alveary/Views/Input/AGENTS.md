## Composer Behavior

These instructions cover composer-specific view code under `Alveary/Views/Input/`.

> **READ FIRST — Focus and keyboard rules are centralized.** Before touching `@FocusState`, `.focusedSceneValue`, `.onKeyPress`, or `.keyboardShortcut` in this folder, consult the **Focus And Keyboard Coordination** section in `Alveary/Views/AGENTS.md`. The production AppKit body consumes first-responder request tokens through `BlockInputView.focusEditor()` and should not add another focus path.

## BlockInputKit Ownership

- Production composer editing is BlockInputKit-owned. Do not reimplement editor projection, completion UI, drops, undo, selection, IME behavior, copy/paste, or sizing behavior in Alveary.
- `AppKitChatComposerBodyView` owns only Alveary shell chrome around `BlockInputView`: editor background/border drawing, focus-token consumption, stop confirmation, and preferred-height invalidation.
- Keyboard behavior for Enter, Shift+Enter, Option+Enter, and Escape must use `BlockInputConfiguration.keyboardShortcuts`. Do not add composer key interception outside BlockInputKit APIs.
- Composer visible height must use BlockInputKit visible-line sizing. Keep Alveary-side layout as preferred-height invalidation only; do not reintroduce custom grow/shrink min/max-height logic.
- File and image drops should stay BlockInputKit-owned. Images can render as images in the editor and are sent as Markdown.

## Drafts And Sending

- BlockInput Markdown is the sendable composer text. `ComposerDraft.messageText` returns the stored Markdown directly.
- Hot-path BlockInput mutations should update only cheap state such as effective emptiness and dirty revisions. Markdown serialization belongs in coalesced document-change publishing or explicit `flushDraftFromEditor()` calls before send/queue/steer flows.
- Programmatic app-owned draft replacements should go through `replaceInputDraft` / `clearInputDraft` so the bridge sees a revisioned external replacement without resetting selection for self-publishes.
- `ChatComposerTextSupport` is not an editor helper. Keep it limited to shared presentation labels, progress placeholders, effective-empty checks for string fallbacks, and legacy transcript `@` mention chip rendering.

## Worktree Picker And Session Location

- The worktree-location picker is an empty-thread-only control for git-backed threads. New threads seed `AgentThread.useWorktree` from the global `createWorktreeByDefault` setting, the picker edits that per-thread override before first send, and it should disappear once `hasCompletedInitialSetup` flips true.
- Once hidden, surface the committed location as `"Local"` or `"Worktree (<last-path-component of worktreePath>)"` in the action row.
- Production gating belongs in `ChatView.sessionLocationLabel`; require both `project.isGitRepository` and `thread.hasCompletedInitialSetup`.
- Format labels through `ChatComposerTextSupport.sessionLocationLabel(useWorktree:worktreePath:)` so tests and snapshots move with any copy change.

## Composer Action Row

- Keep renderer-neutral decisions in `ComposerPresentation` and `ComposerSettingsPresentation`.
- Keep presentation pure: compute labels, disabled states, placeholders, action copy, busy return behavior, effort options, and trust blocking from caller-owned inputs.
- Keep effects elsewhere: no draft mutation, persistence, settings writes, tasks, or service calls in presentation types.
- `ChatComposerActionRow` owns the bottom settings/action row; `ChatComposerActionRowView` owns native AppKit rendering inside the production panel.
- Native controls that custom-draw dynamic `NSColor`s must resolve colors through `appKitRenderingAppearance` and invalidate display from `viewDidChangeEffectiveAppearance()`.
- `ComposerMode.ProgressReason.canStop` is the single source of truth for whether the action slot renders a stop button and whether Escape stop confirmation is armed.
- Tool-specific waiting copy for deferred tools must flow through the `ComposerMode.ProgressReason.toolApproval(...)` payload, not through new `toolName` switches.
- The action row height is 30pt, matching `.regular` `ProminentActionButtonStyle`. Keep native primary/stop button heights, disabled send footprint, and progress slots in lockstep so the composer does not shift vertically.
- Stop confirmation lives inside the stop button label. The first Escape arms `isStopConfirmationArmed` and expands the button to `Confirm`; timeout or any state where `canUseEscapeToStop == false` must clear it.

## Staged Context

- Queued-message edit, rollback, send, steer, and session-handoff draft flows must preserve `stagedContext` unless the user explicitly dismisses it.
- Native queued-message rows render queued text as Markdown with the composer inline-code palette and legacy `@` mention chips. This keeps BlockInput Markdown links/images visible while preserving old stored mention rendering.
