## Conversation Tab Row

Rules for `ThreadDetailView+ConversationTabs.swift` and the `ConversationTabPresentation` values it renders from.

> **READ FIRST:** Focus and keyboard rules are centralized in `Alveary/Views/AGENTS.md`.

## Chips And Rename

- Mount `ThreadDetailConversationTabs` only after initial setup and only for more than one resolved live conversation. The strip has no single-conversation label or creation control; additional conversations are created from the thread title toolbar action.
- **Chips render from `ConversationTabPresentation` values and never store a `Conversation`** — the strip re-runs from its own `@State` after a delete can commit, and a model read there traps. `ThreadDetailView` builds the presentations per body pass (`Alveary/Views/Chat/ThreadDetail/ThreadDetailView+ConversationTabPresentations.swift`); actions hand back the presentation and handlers re-resolve by `conversationModelID`.
- While mounted, the strip sits between the unconditional root toolbar hairline and its own bottom `.paneHeader` hairline.
- Render tabs through `SelectableTabChip` in `Alveary/Views/Components/TabChips/`.
- Keep chip fills `.standard` so inline-code color does not change on selection.
- Use `TabChipStatusIndicator.spinner(.secondary)` for `.busy` in the same fixed 8x8 slot as dots.

### Inline Rename

- Inline rename uses `editingConversationID` in `ConversationTabChip`; do not replace it with a modal.
- Editing chips use the Finder-style text background plus 1pt accent stroke.
- Suppress the close button with `.tabChipShell(..., showsCloseButton: false)` so width stays stable.
- Gate context-menu rename and the VoiceOver rename action on `editingConversationID == nil`.
- Do not allow switching rename targets mid-edit; SwiftUI can leave the new row stuck without a field.

### Header Chrome

- Keep full-capsule press feedback and hit area. Do not hand-roll a status-dot + label + close capsule.
- Keep the header's system `.bar` background and add separators as overlays.
- Render the bottom header separator with `AppSeparatorHairline(surface: .paneHeader)` so its physical-pixel thickness and resolved tint match the titlebar separator.

## Shortcuts And Removal

- Attach ⌘1 through ⌘9 to each visible select button in the conversation row.
- Handle ⌘W with one invisible enabled `ConversationCloseShortcutSink` in
  `ThreadDetailView`'s background.
    - Mount it independently of the visual tab strip and guard internally for inline rename or one-tab states.
    - Use `.background`, not a zero-sized HStack sibling.
    - Set `.id(selectedTab?.conversationModelID)` so the closure tracks current selection.
    - Use enabled no-op guards; disabled shortcut buttons let ⌘W fall through to Close Window.
    - Keep it out of `.commands` / `CommandGroup` because those surface in the menu bar and can lose to default close handling.

### Removal Safety

- When closing the selected tab, select the visual neighbor first: next, then previous.
- `onRemove` must re-check the tab count before presenting confirmation.
- The original main conversation of a scheduled-run Task is durable provenance and is never removable. Hide its close affordance, consume Cmd-W as a no-op, and keep the commit-time guard for stale UI actions.
- Arm the confirmation with `ThreadDetailPendingConversationRemoval` values; the Remove button passes its stored identifiers into `removeConversation(...)` and never reads a model.
- Do not re-resolve a `Conversation` only to read `.id`; `modelContext.model(for:)` can return a zombie. See `Alveary/Data/AGENTS.md`.

## Scroll Hooks

- Wrap the multi-tab row in `ScrollViewReader`.
- Tag each chip with `.id(tab.conversationModelID)`.
- The trailing sentinel is `Color.clear.frame(width: 12)` with `.id(ScrollTarget.trailingSentinel)`.
    - It reserves the visible 12pt gap before the overlay divider.
    - It is also the scroll target for the content's absolute trailing edge.
    - Put it in the outer `HStack(spacing: 0)`, after the inner chip HStack.
    - Do not add separate trailing padding; that doubles the end gap.
- Scroll on selection with `onChange(of: selectedConversationModelID, initial: true)`.
    - Last-chip selections target the sentinel with `anchor: .trailing`.
    - Mid-row selections use the chip ID with default anchor.
- Scroll on count growth only (`newCount > oldCount`) and target the sentinel. This surfaces newly appended conversations without running on removal.

## Divider And Layout

- Only the trailing divider exists; there is no leading fixed element for a leading divider to abut.
- Drive divider visibility from `onScrollGeometryChange`, not `GeometryReader` preferences.
- Compute overflow with `effectiveMaxScroll = tabsMaxScrollableDistance - tabsTrailingSentinelWidth`, comparing it against the inset-corrected scroll distance that `Alveary/Views/Components/TabChips/AGENTS.md` mandates.
- Render the divider as `.overlay(alignment: .trailing)` on the `ScrollView`.
- Keep divider tint and 18pt height matched with the terminal-pane divider.
- Do not use `.contentMargins(.trailing, ...)`; macOS 26 did not reserve visible trailing space here.
- Keep the multi-tab `ScrollView` greedy with `.frame(maxWidth: .infinity)`.
- Keep the 20pt pane-edge inset inside scrollable content.
    - The chip HStack gets `.padding(.leading, 20)`.
- The 12pt pre-divider gap is the sentinel width, not a non-scrollable reserved band.
- `testConversationTabsOverflow` guards the greedy-ScrollView layout.
- The trailing divider is not captured in that baseline because geometry updates after snapshot display. Verify divider changes manually in the running app.
