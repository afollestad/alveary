## Shared Components

General shared controls live here. Narrower scopes:

- `Accent/AGENTS.md`: `AppAccentFill`, accent-derived `NSColor`.
- `AppKit/AGENTS.md`: shared AppKit-only primitives.
- `Markdown/AGENTS.md`: `AppMarkdown*`, inline labels, code palettes.
- `TabChips/AGENTS.md`: `SelectableTabChip`, `TabChipButtonStyle`.
- `TextInput/AGENTS.md`: `AppTextEditor`, `AppKitTextView`.

## Status Spinners

- Use `StatusIndicatorSpinner` for fixed-size status spinner slots: the 8pt status-dot slots (sidebar rows, tab chips) and the 16pt `PrimaryToolbarProgressSlot`. Do not shrink `ProgressView` into dot slots.
- AppKit transcript rows (tool status, task lists) use the `AppKit/AppKitStatusIndicatorSpinner` twin instead of `NSProgressIndicator`; keep the two rings visually matched (track at 25% alpha, 0.7 arc, same spin period).
- Working spinners are `.secondary` gray, not blue — the spinning shape carries the "working" signal; blue stays reserved for `.waitingForUser` dots. See **Status Dot Colors** in `Alveary/Views/AGENTS.md`.
- Only `rotationEffect` animates; the frame stays fixed so busy/idle swaps cannot change row or chip layout.
- Snapshot determinism comes from the `statusSpinnerAnimationsDisabled` environment key, set by the shared snapshot hosts. `\.accessibilityReduceMotion` is get-only and cannot be injected in tests; the spinner still reads it for real reduce-motion users. The AppKit twin needs no hook: its spin is a presentation-only `CABasicAnimation`, so snapshots render the static model layer.

## Disabled Cursor

- Use `blockedCursorOverlay(when:)` for disabled SwiftUI controls that should show the macOS blocked cursor. AppKit text editors use `showsDisabledCursor` instead.

## Selectable Rows

- `SelectableRowModifier` in `SelectionRowBackground.swift` owns press highlight and action through one `DragGesture(minimumDistance: 0)`.
- Keep the movement guard so long clicks still fire but drags do not.
- Do not replace it with `.onTapGesture`; macOS drops long-held taps after the press highlight appears.
- Keep the sibling `.accessibilityAction { action() }` so VoiceOver activation works.
- Keep the pending-selection state for click releases; it bridges mouse-up to model publication so rows do not visually flash clear before becoming selected.
- Pass a stable row identity when selectable rows can be inserted, removed, or reordered so transient press/pending state cannot leak into recycled `List` rows.
- Keep selectable row background insets at their 10pt defaults unless a surface must compensate for host chrome to hit a measured visual edge.

## Split Buttons

- Use `SplitActionButton` for one primary click target plus a trailing caret menu.
- The left side runs the selected option; the menu only changes selection.
- Reuse the shared chrome instead of hand-rolling an `HStack` divider and menu.
- Keep SwiftUI `Menu` out of the chrome. The component uses AppKit `NSMenu` to avoid snapshot indicator leaks and height inflation.

## Expandable Headers

- Use `AppHeaderToggle` for compact expand/collapse headers that need the AppKit mouse fallback.
- Pair `withAnimation(appExpansionAnimation)` with `.appExpansionAnimationOverride(value:)` so header toggles and surrounding lazy-list reflow share timing.

## Hover Info Popups

- Use `AppHoverInfoIcon` / `AppKitHoverInfoButton` for `info.circle` help affordances instead of plain `.help(...)` when the app needs the custom Alveary tooltip chrome.
- Keep info icons visually stable: center them relative to the adjacent label text and use the shared muted gray treatment regardless of the parent row's enabled or selected state.
- Keep tooltip sizing content-led but bounded. Short text should wrap content width; long text should wrap within the shared maximum width, use balanced horizontal/vertical insets, and keep the bubble shadow.
- Prefer placing the tooltip to the trailing side of the icon when there is horizontal room, falling back to vertical placement only when needed.
- Preserve accessibility value/help on the info button so the custom hover popup does not replace screen-reader help.
