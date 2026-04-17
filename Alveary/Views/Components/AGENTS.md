## Shared View Components

These rules cover shared UI components under `Alveary/Views/Components/`.

## Selectable Row Gestures

- `SelectableRowModifier` in `SelectionRowBackground.swift` drives both the press highlight and the click action from a single `DragGesture(minimumDistance: 0)`: `onChanged` sets the highlight, `onEnded` clears it and calls the row action as long as the pointer didn't move far. Do not revert to `.onTapGesture` (alone or alongside `.onLongPressGesture(minimumDuration: .infinity, pressing:)`): SwiftUI's tap gesture on macOS stops firing when a click is held past its short-click window, so the background highlights on mouse-down but mouse-up after a longer hold does nothing. Keep a sibling `.accessibilityAction { action() }` so VoiceOver activation still invokes the row.

## AppMarkdownInlineLabel

- Use `AppMarkdownInlineLabel` (not raw `Text`) for any single-line label that renders a user-provided string which may contain inline markdown code, such as sidebar thread rows and conversation tab chips. The label segments the string and renders inline code via `AppMarkdownInlineCodeChip` clamped to the surrounding text's line height so the chip's rounded background visually overflows into the parent's vertical padding without inflating row/tab height.
- The label's `textStyle` parameter drives both the SwiftUI text font and the chip font size; keep them paired by always passing a single `NSFont.TextStyle` rather than reintroducing independent `font` and chip-size parameters.

## AppTextEditor And AppKitTextView

- Keep the placeholder drawn inside `AppKitTextView` instead of reintroducing a SwiftUI overlay so it shares the real `NSTextView` insets and caret positioning.
- Selection-change callbacks for `AppKitTextView` must not synchronously trigger layout-dependent restyling such as chip rect calculation or `NSLayoutManager.ensureLayout(for:)`; update lightweight typing state inline, but defer full restyles to the next main-runloop turn to avoid AppKit reentrancy traps.
