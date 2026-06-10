## Conversation Tab Row

Rules for `ThreadDetailView+ConversationTabs.swift`.

> **READ FIRST:** Focus and keyboard rules are centralized in `Alveary/Views/AGENTS.md`.

## Chips And Rename

- Render tabs through `SelectableTabChip` in `Alveary/Views/Components/TabChips/`.
- Keep chip fills `.standard` so inline-code color does not change on selection.
- Use `TabChipStatusIndicator.spinner(.secondary)` for `.busy` in the same fixed 8x8 slot as dots.
- Inline rename uses `editingConversationID` in `ConversationTabChip`; do not replace it with a modal.
- Editing chips use the Finder-style text background plus 1pt accent stroke.
- Suppress the close button with `.tabChipShell(..., showsCloseButton: false)` so width stays stable.
- Gate context-menu rename and the VoiceOver rename action on `editingConversationID == nil`.
- Do not allow switching rename targets mid-edit; SwiftUI can leave the new row stuck without a field.
- Keep full-capsule press feedback and hit area. Do not hand-roll a status-dot + label + close capsule.
- Keep the header's system `.bar` background and add separators as overlays.

## Shortcuts And Removal

- Attach ⌘1 through ⌘9 to each visible select button in the multi-conversation branch.
- Handle ⌘W with one invisible enabled button in the tab bar background.
    - Mount it unconditionally and guard internally for inline rename or one-tab states.
    - Use `.background`, not a zero-sized HStack sibling.
    - Set `.id(selectedConversation.persistentModelID)` so the closure tracks current selection.
    - Use enabled no-op guards; disabled shortcut buttons let ⌘W fall through to Close Window.
    - Keep it out of `.commands` / `CommandGroup` because those surface in the menu bar and can lose to default close handling.
- When closing the selected tab, select the visual neighbor first: next, then previous.
- `onRemove` must re-check `conversations.count > 1` before presenting confirmation.
- In the confirmation button, capture `persistentModelID` and the UUID-string `id` synchronously and pass both into `removeConversation(...)`.
- Do not re-resolve a `Conversation` only to read `.id`; `modelContext.model(for:)` can return a zombie. See `Alveary/Data/AGENTS.md`.

## Scroll Hooks

- Wrap the multi-tab row in `ScrollViewReader`.
- Tag each chip with `.id(conversation.persistentModelID)`.
- The trailing sentinel is `Color.clear.frame(width: 12)` with `.id(ScrollTarget.trailingSentinel)`.
    - It reserves the visible 12pt gap before the overlay divider.
    - It is also the scroll target for the content's absolute trailing edge.
    - Put it in the outer `HStack(spacing: 0)`, after the inner chip HStack.
    - Do not add separate trailing padding; that doubles the end gap.
- Scroll on selection with `onChange(of: selectedConversation.persistentModelID, initial: true)`.
    - Last-chip selections target the sentinel with `anchor: .trailing`.
    - Mid-row selections use the chip ID with default anchor.
- Scroll on count growth only (`newCount > oldCount`) and target the sentinel. This surfaces newly appended conversations without running on removal.

## Divider And Layout

- Only the trailing divider exists; there is no leading fixed element for a leading divider to abut.
- Drive divider visibility from `onScrollGeometryChange`, not `GeometryReader` preferences.
- Compute overflow with `effectiveMaxScroll = tabsMaxScrollableDistance - tabsTrailingSentinelWidth`.
- Render the divider as `.overlay(alignment: .trailing)` on the `ScrollView`.
- Keep divider tint and 18pt height matched with the terminal-pane divider.
- Do not use `.contentMargins(.trailing, ...)`; macOS 26 did not reserve visible trailing space here.
- Keep the multi-tab `ScrollView` greedy with `.frame(maxWidth: .infinity)`.
- Use `Spacer()` only in the single-conversation label branch.
- Keep the 20pt pane-edge inset inside scrollable content.
    - Multi-tab HStack gets `.padding(.leading, 20)`.
    - Single label branch pads the label directly; it may use a calibrated value when SwiftUI rendering measures one point off from the desired 20pt visual inset.
- The 12pt pre-divider gap is the sentinel width, not a non-scrollable reserved band.
- `testConversationTabsOverflow` guards the greedy-ScrollView layout.
- The trailing divider is not captured in that baseline because geometry updates after snapshot display. Verify divider changes manually in the running app.
