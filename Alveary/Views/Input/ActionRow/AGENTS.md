## Composer Action Row

These instructions cover `Alveary/Views/Input/ActionRow/` — the settings and action controls under the composer editor, the buttons in that row, and the popovers they open. The reasoning popover is `Alveary/Views/Input/Reasoning/AGENTS.md`; the editor above the row is `Alveary/Views/Input/Editor/AGENTS.md`.

> **READ FIRST — Focus and keyboard rules are centralized.** Before touching `@FocusState`, `.onKeyPress`, or `.keyboardShortcut` here, consult the **Focus And Keyboard Coordination** section in `Alveary/Views/AGENTS.md`.

### Ownership

- **`ChatComposerActionRow` owns the row; `ChatComposerActionRowView` owns its native AppKit rendering.** Keep renderer-neutral decisions in `ComposerPresentation` and take option lists from the caller.
- **Keep presentation pure and effect-free.** Labels, disabled states, placeholders, action copy, busy return behavior, effort options, and trust blocking all compute from caller-owned inputs; no draft mutation, persistence, settings writes, tasks, or service calls in presentation types.
- **Menus are presentation-only.** File picking, BlockInputKit insertion, plan-mode mutation, the Task Workspace directory picker (`AppKitChatComposerPanelView`), and its validation, persistence, and reconfiguration (`ConversationViewModel`) all stay callbacks. Provider and model options arrive from `AgentProviderDiscoveryService` through the caller — the row must not discover providers, refresh models, or read provider config.

### Rendering

- **When adding a rendered value to `Configuration`, add it to `AppliedConfigurationSnapshot` too**, or the row will not repaint when only that value changes — `configure(_:)` skips `applyConfiguration` on an unchanged snapshot. State the row mutates outside `configure`, such as the reasoning display-selection override, must repaint its own control.
- **Keep the row 30pt**, matching `.regular` `ProminentActionButtonStyle`, with native primary/stop button heights, the disabled send footprint, and progress slots in lockstep so the composer cannot shift vertically. The leading `+` button stays square to the dropdown height, its default, hover, pressed, focused, and disabled states clipped to the same circular background.
- **Resolve custom-drawn dynamic `NSColor`s through `appKitRenderingAppearance`** and invalidate display from `viewDidChangeEffectiveAppearance()`.
- **`ComposerMode.ProgressReason.canStop` is the single source of truth** for whether the action slot renders a stop button and whether Escape stop confirmation is armed. That confirmation lives inside the stop button label: the first Escape arms `isStopConfirmationArmed` and expands the button to `Confirm`; a timeout, or any state where `canUseEscapeToStop == false`, clears it.
- **Tool-specific waiting copy for deferred tools flows through `ComposerMode.ProgressReason.toolApproval(...)`**, never a new `toolName` switch.

### Popovers

Shared popover surface and divider chrome belongs to `Alveary/Views/Components/AppKit/AGENTS.md`.

- **Every composer popover opens above its anchor; none open downward.** Derive the edge from the anchor's `isFlipped` through `ComposerReasoningMenuPresenter.upwardEdge(for:)`, whose doc comment owns the coordinate-space rule.
- **Menu-anchor buttons fire on mouse-up**; do not switch them to mouse-down activation (explicit user decision).
- **Permission rows wrap subtitles to at most two lines**, measured per option by `ComposerPermissionMenuMetrics.rowHeight(for:)`, and always reserve the trailing icon slot so selection cannot change wrap width. Reasoning rows stay single-line.

#### Plus Menu

- **The app-shot row is a caller-owned input, not a capability the menu discovers.**
    - **Take the app name and icon pre-resolved.** `Configuration.appShotAttachment` carries an `NSImage` the service layer already published. Opening the menu must never call `NSWorkspace.urlForApplication(withBundleIdentifier:)` — that LaunchServices query would run synchronously while the popover builds.
    - **Scale, do not resize.** Full-resolution icons fill the shared slot through `ComposerPlusMenuRowView.iconScaling`, matching `AppKitAppShotAttachmentCardView`. Do not mutate a shared `NSImage`'s `size`, and do not mark an app icon `isTemplate` or the row's `contentTintColor` flattens it.
    - **Hide the row when nothing is attachable**, and take the menu's height from `ComposerPlusMenuMetrics.contentSize(includesAppShotRow:)`.
    - **Only request the capture.** The action raises the app-shot trigger; the app root owns destination routing, permissions, and staging.
    - **Keep it out of `AppliedConfigurationSnapshot`.** The menu rebuilds from the stored configuration on each open, so including these values would force a full relayout on every foreground app switch.

#### Worktree Picker

- **The picker is an empty-thread-only control for git-backed threads.** New threads seed `AgentThread.useWorktree` from the global `createWorktreeByDefault` setting; the picker edits that per-thread override before first send and disappears once `hasCompletedInitialSetup` flips true.
- Once hidden, do not surface redundant `Local` or `Worktree (<name>)` text in the row — the sidebar owns committed worktree indication.
