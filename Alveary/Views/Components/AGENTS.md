## Shared Components

General shared controls live here. Narrower scopes:

- `Accent/AGENTS.md`: `AppAccentFill`, accent-derived `NSColor`.
- `Markdown/AGENTS.md`: `AppMarkdown*`, inline labels, code palettes.
- `TabChips/AGENTS.md`: `SelectableTabChip`, `TabChipButtonStyle`.
- `TextInput/AGENTS.md`: `AppTextEditor`, `AppKitTextView`.

## Disabled Cursor

- Use `blockedCursorOverlay(when:)` for disabled SwiftUI controls that should show the macOS blocked cursor. AppKit text editors use `showsDisabledCursor` instead.

## Selectable Rows

- `SelectableRowModifier` in `SelectionRowBackground.swift` owns press highlight and action through one `DragGesture(minimumDistance: 0)`.
- Keep the movement guard so long clicks still fire but drags do not.
- Do not replace it with `.onTapGesture`; macOS drops long-held taps after the press highlight appears.
- Keep the sibling `.accessibilityAction { action() }` so VoiceOver activation works.

## Split Buttons

- Use `SplitActionButton` for one primary click target plus a trailing caret menu.
- The left side runs the selected option; the menu only changes selection.
- Reuse the shared chrome instead of hand-rolling an `HStack` divider and menu.
- Keep SwiftUI `Menu` out of the chrome. The component uses AppKit `NSMenu` to avoid snapshot indicator leaks and height inflation.
