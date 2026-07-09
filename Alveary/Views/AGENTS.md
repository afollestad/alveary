## SwiftUI View Composition

These are view-layer defaults for files under `Alveary/Views/` unless a narrower `AGENTS.md` overrides them.

- In SwiftUI, prefer extracted `View` types over `some View` extension properties. Keep trivial one-off stacks inline, and only extract when it clarifies composition.
- When an extracted child view is used by another view, place it in the same folder with `Parent+Child.swift` naming such as `DiffViewerPane+Header.swift`.
- For SwiftUI buttons, use the shared `primaryActionButtonStyle()`, `secondaryActionButtonStyle()`, and `destructiveActionButtonStyle()` modifiers from `Components/ActionControls.swift`. Reserve `.plain` and `.borderless` for low-emphasis affordances.
- For icon-bearing action buttons that use the shared prominent button styles, prefer explicit `Image` + `Text` content over `Label`; on macOS the shared style can render `Label` as text-only in some contexts.
- For selectable list rows such as sidebar items, settings tabs, and diff file lists, use the `.appSelectableRow(...)` modifier from `Components/SelectionRowBackground.swift`. It bundles `contentShape`, tap gesture, press-highlight feedback, accessibility selection traits, and `listRowBackground` into a single call. Do not use `Button` with `.plain` style for list rows.
- Markdown rendering is local SwiftUI `Text`/layout code; keep clickable rows free of nested hit-test blockers.

## Responsive Settings Rows

- **Use `SettingsResponsiveControlRow` for settings label/control rows.** Default controls take 50% horizontally; compact controls can use intrinsic sizing.
- **Use `SettingsFormSection` and `SettingsFormRow` for app settings forms.** They keep section cards and row alignment consistent.
- **Use `SettingsToggleRow` for boolean app settings.** It preserves switch styling, row-click toggling, press feedback, and accessibility actions.
- **Use intrinsic sizing for compact controls.** Pickers and compact steppers hug the shared minimum width horizontally, then fill when stacked.
- **Keep switches inline.** Toggle controls use intrinsic inline sizing because the switch is small enough to stay beside the label.
- **Preserve layout measurement semantics.** Use ideal horizontal sizing only when SwiftUI proposes no width; use actual width during placement so cramped rows stack instead of overflowing.
- **Keep settings navigation reachable.** Switch `SettingsScreen` from the side list to compact tabs before the side list can be clipped.

## Status Dot Colors

Cross-surface color mapping for status dots/chips in `Sidebar/`, `Chat/`, and `Terminal/`. Current surfaces: `SidebarThreadRow.statusColor`, `ConversationTabChip.statusColor`, and `TerminalSessionChip.statusColor`.

- **Blue** = waiting runtime state (`.waitingForUser` dots). Working states (`.busy`, `.running`) render the shared gray ring spinner (`.secondary`), not a blue dot — the spinning shape carries the "working" signal, so its color stays neutral next to inert gray dots.
- **Green** = done / success (`.unread`, `.succeeded`). Inline transcript tool rows are the muted shape-only exception documented in `Alveary/Views/Chat/Blocks/Tools/AGENTS.md`.
- **Red** = error (`.error`, `.failed`).
- **Orange** = user-cancelled (`.cancelled`).
- **Secondary** = inert (`.stopped`, `.archived`).
- **How to apply:** A new status-dot surface must follow this mapping — do not pick colors per surface. Cases mean the same thing across enums (a `.busy` thread and a `.running` terminal session are both "in-progress"), so they must share a color even though their enum case names differ.
- **Why:** Before this was unified, `.busy` rendered green in sidebar and conversation tabs while `.succeeded` rendered blue in terminal chips — the same color meant opposite things on different surfaces. A green dot could mean "working" or "done" depending on where you looked.

## Focus And Keyboard Coordination

**This section is the single source of truth for cross-surface focus and keyboard rules.** The nested `Sidebar/`, `Input/`, and `Chat/` AGENTS.md files each open with a "READ FIRST" callout pointing here instead of duplicating these rules — when you change anything below, keep those callouts accurate but do *not* re-inline the details into the nested files.

These rules apply anywhere a view introduces a new `@FocusState`, `.onKeyPress`, or `.keyboardShortcut`. Scope-specific notes (e.g. sidebar's own keyboard-navigation traversal order) still live in the nested AGENTS.md.

- The sidebar `List` (`Alveary/Views/Sidebar/SidebarView.swift`) owns an `@FocusState var isKeyboardFocused` so its `.onKeyPress` fires after mouse interaction. Cross-surface release to the composer is bundled into `claimSidebarFocus()`, which calls `chatComposerFocus?.release()` *before* setting `isKeyboardFocused = true`. The native composer publishes a `ChatComposerFocusHandle` through `.focusedSceneValue(\.chatComposerFocus, ...)` (key in `Alveary/Views/Input/ChatComposerFocus.swift`) and sibling views read it with `@FocusedValue`.
- Call `claimSidebarFocus()` from **every** explicit user-action site that should make the sidebar the active keyboard surface: the `selectedSidebarItem` `.onChange` (covers context-menu archive/delete and external routing), expansion toggles, and **every row-tap action** (`activateThread`, `activateProject`, top-level rows). The row-tap calls cannot be replaced by the `selectedSidebarItem` `.onChange` alone — re-tapping the *already-selected* row does not mutate `selectedSidebarItem`, so the change handler never fires and the composer would otherwise keep AppKit first-responder while the user expects arrow keys to drive the sidebar.
- Thread-creation commands (⌘N, the sidebar project row `+` button, the project context-menu "New Thread") want the opposite of sidebar focus — the user intends to start typing immediately:
    - Call `appState.requestComposerFocus()` *before* mutating `appState.selectedSidebarItem`. It sets `pendingComposerFocusToken`; while that token is non-nil, the sidebar's `.onChange(of: selectedSidebarItem)` skips its `claimSidebarFocus()` call.
    - The production composer plumbs the token to `BlockInputView.focusEditor()` as a plain `requestFirstResponder: UUID?` value. It tracks the consumed focus request token; on a new non-nil token it focuses BlockInputKit directly with a short retry loop (window attachment can span multiple render passes on a brand-new thread), then calls `onFocusRequestConsumed` which clears the token.
    - `claimSidebarFocus()` clears `pendingComposerFocusToken` before claiming, so if the user takes an explicit sidebar action between `requestComposerFocus()` and the composer's consumption of the token (e.g. ⌘N followed immediately by clicking a different row), the stale request is cancelled and the newly-mounted composer no longer steals first responder back.
- **Do not claim composer focus by writing to a `@FocusState` binding.** The production composer routes programmatic focus through `requestFirstResponder` tokens and BlockInputKit focus APIs. New production focus paths must use `ChatComposerFocusHandle` or the token-driven BlockInput path.
- Inline sidebar rename (`editingThreadID != nil`) must suppress the sidebar's `.onKeyPress` handling entirely. `handleSidebarKeyPress` early-returns `.ignored` while a row is being renamed so arrow keys, Return, and Delete stay inside the `TextField` and don't mutate `selectedSidebarItem` out from under the editor. `handleRenameKey()`'s own guard against re-entering edit mode is not sufficient because the other cases still navigate or delete.
- Do **not** route the composer-release through `.onChange(of: isKeyboardFocused)`. SwiftUI's `.focused($isKeyboardFocused)` reactively flips the state to `true` whenever the focusable List re-claims AppKit first responder (including right after the user clicks the composer), and routing the release through that change handler steals focus back from the composer on every click. Releasing only at the explicit action sites avoids the feedback loop.
- `syncFocusIfNeeded()` in `Alveary/Views/Components/TextInput/AppTextEditor+AppKit.swift` may claim AppKit first responder when the focus binding is `true`; it must not force-resign when the binding becomes `false`. A symmetric resign branch races with click-to-focus and can make the composer non-interactive. Cross-surface release relies on SwiftUI callers such as `claimSidebarFocus()` clearing `chatComposerFocus` before claiming their own focus.
- Modifier-key shortcuts (⌘W, ⌘1..9, etc.) should be attached with `.keyboardShortcut()` on buttons that stay in the window hierarchy, or registered via `.commands { CommandGroup(...) }` from the scene. Those dispatch through the scene/responder chain and are focus-independent, so they fire correctly even when the sidebar has just grabbed `@FocusState`. Do not bury a shortcut-bearing button inside a conditionally-rendered branch (e.g. gated on `hasVisibleChatContent`) — the shortcut disappears when that branch is not mounted.
- Non-modifier `.onKeyPress` handlers added to a new surface (e.g. arrow keys in a transcript) would conflict with the sidebar's focus grab and need their own coordination strategy. Follow the sidebar/composer pattern: publish a `FocusedSceneValue` for the new surface, consume it from whichever sibling should release, and release on takeover.
