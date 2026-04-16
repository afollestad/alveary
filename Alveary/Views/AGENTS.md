## SwiftUI View Composition

These are view-layer defaults for files under `Alveary/Views/` unless a narrower `AGENTS.md` overrides them.

- In SwiftUI, prefer extracted `View` types over `some View` extension properties. Keep trivial one-off stacks inline, and only extract when it clarifies composition.
- When an extracted child view is used by another view, place it in the same folder with `Parent+Child.swift` naming such as `DiffViewerPane+Header.swift`.
- For SwiftUI buttons, use the shared `primaryActionButtonStyle()`, `secondaryActionButtonStyle()`, and `destructiveActionButtonStyle()` modifiers from `Components/ActionControls.swift`. Reserve `.plain` and `.borderless` for low-emphasis affordances.
- For icon-bearing action buttons that use the shared prominent button styles, prefer explicit `Image` + `Text` content over `Label`; on macOS the shared style can render `Label` as text-only in some contexts.
- For selectable list rows such as sidebar items, settings tabs, and diff file lists, use the `.appSelectableRow(isSelected:action:)` modifier from `Components/SelectionRowBackground.swift`. It bundles `contentShape`, tap gesture, press-highlight feedback, accessibility selection traits, and `listRowBackground` into a single call. Do not use `Button` with `.plain` style for list rows.
- `InlineText` from Textual applies `TextSelectionInteraction()` internally, which consumes clicks and blocks `.onTapGesture` on any containing row (including `.appSelectableRow`). Add `.allowsHitTesting(false)` to `InlineText` when it is rendered inside a clickable row so taps reach the row's gesture. Plain `Text` does not need this.
