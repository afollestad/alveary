## Chat Composer Panel

These instructions cover `Alveary/Views/Chat/Composer/` — the AppKit panel the chat composer sits in: its chrome, the content above the editor, and the interaction overlays that cover it. The editor inside it is BlockInputKit's and `Alveary/Views/Input/Editor/AGENTS.md` owns that bridge; dictation is `Alveary/Views/Chat/VoiceInput/AGENTS.md`.

> **READ FIRST — Focus and keyboard rules are centralized.** Before touching `@FocusState`, `.onKeyPress`, or `.keyboardShortcut` here, consult the **Focus And Keyboard Coordination** section in `Alveary/Views/AGENTS.md`.

**Keep a rule here only when the code that would violate it is not the code that documents it.** Mechanism whose only reader is its own file belongs in a doc comment: `AppKitComposerOverlayAccessory`'s `ExitPlanMode`-only slot and unchanged `AskUserQuestion` geometry, `accessoryButton`'s stored lifetime, `isAccessoryEnabled`'s single enablement rule, and `accessoryControls`' place in the key-view loop each carry theirs. `ComposerCompactDropdownButton` documents its own claim on `Return` and `Space`, which is why those two never reach the panel from a focused accessory.

### The Panel Shell

- **`AppKitChatComposerPanelView` owns the shell.** Transparent outer background, horizontal padding, top-content vertical offset, top divider, and panel measurement belong there rather than to a SwiftUI parent.
- **Production routes everything through the native panel.** Active `ChatView` hands it `ChatComposerActionRowView`, pending queued messages (`AppKitChatQueuedMessagesView`, above the composer body), the BlockInputKit editor bridge, preferred-height invalidation, and shortcut configuration. A production fix must not re-enter a SwiftUI editor stack.
- **Top content is native so it measures with the editor.** Last-turn errors, session-continuity notices, and staged-context banners render through `AppKitChatComposerTopContentView`, sharing the editor and action row's coordinate space for height and hit testing. Staged context stays there; it never becomes a transcript row.
- **One owner per clearance edge.** Editor-to-action-row spacing comes from `AppKitChatComposerPanelView.Layout.actionRowSpacing`; do not stack it with native panel spacing.
- **The scrolled-up top separator is the panel's own overlay**, not a parent overlay or a child inside the background fill — an overlaid divider cannot clip when vertical panel padding is small.
- **Do not reintroduce a changed-files strip above the composer.** Diff status belongs on the toolbar button that opens the Diff Viewer, so changed-file loading cannot alter composer height or strand transcript measurements.

### Interaction Overlays

- **`AskUserQuestion` and `ExitPlanMode` confirm over the composer, not in the transcript.** `ExitPlanMode` leaves the plan markdown a transcript row; only the approval moves.
- **Keep the normal composer mounted underneath**, cover it with the full-bounds hit-test blocker, measure the overlay as the active composer height, and preserve transcript follow and anchor behavior across that height change.
- **Keep overlay interaction native.** Shared `AppKitComposerOverlay*` controls own row focus, hover and pressed states, shortcut badges, and keyboard routing. Rows must be focusable: `Up`/`Down` move between options, `Tab` reaches options and footer buttons, `Space` selects, `Esc` dismisses, and `Return` selects the focused row then advances or submits.
- **The accessory menu is a composer popover** and follows `Alveary/Views/Input/ActionRow/AGENTS.md`'s rule that they all open upward; this panel is the flipped anchor that rule exists for.
- **Keep the overlay id free of the accessory's selection.** `configure` calls `focusFirstOptionAfterLayout()` only when the id changes, so folding a selection into it re-steals focus on every pick.
- **`configure(nil)` must close the accessory popover.** A popover is a window, and would otherwise outlive the overlay that owns it.
