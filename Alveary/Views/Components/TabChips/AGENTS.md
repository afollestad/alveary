## Shared Tab Chips

Rules for `SelectableTabChip.swift`, `TabChipButtonStyle.swift`, and
`ScrollGeometry+ScrolledDistance.swift`.

- **Gate a scrolling chip strip's edge dividers on `ScrollGeometry.horizontalScrolledDistance`, never on `contentOffset.x` or its magnitude.** A leading content inset biases the raw offset in some window layouts only; the extension's doc comment owns why. All three chip strips use it.
- Use `TabChipButtonStyle(isSelected:)` for pill-shaped selection controls.
- Keep the whole capsule as the hit area; do not wrap only the label in a plain button.
- Put outer padding on the button content, not the chip HStack, so pressed fill covers the full capsule.
- Keep close buttons as trailing `ZStack` overlays with `focusEffectDisabled()`.

### Shell Composition

- `SelectableTabChip` is the shared shell for conversation tabs and terminal session chips.
- Build new tab/chip surfaces on `SelectableTabChip`; layer rename or context-menu affordances around it instead of forking structure.
- Compact filter chips without status or close affordances may use `TabChipButtonStyle` directly with symmetric label padding; do not force `SelectableTabChip`'s reserved slots into filter rows. `PaneFilterChip` is that chip for the pane headers' filter rows — reuse it rather than re-declaring a private twin per screen.
- **A chip-shaped menu wears `TabChipButtonStyle` through `.menuStyle(.button)`.** The ambient `ButtonStyle` draws the capsule, so a `Menu` matches the chips it replaces; hide the system indicator and supply an explicit chevron, or the default one leaks into snapshots. `PaneHeaderFilterDropdown` is the reference.
    - Keep its label truncating with a fixed-size chevron, and give it `layoutPriority(1)` rather than `fixedSize`: it holds a pane's leading edge, so sizing it to content pushes the row past the pane, while plain flexibility lets a trailing spacer squeeze it when there is room.
- Route rename VoiceOver actions through `renameAccessibilityAction:` so the action binds to the select button.
- Use `TabChipStatusIndicator.spinner(...)` / `TabChipStatusIndicatorView` for spinner states in the fixed 8x8 status slot; the spinner renders through the shared `StatusIndicatorSpinner`.

### Slots And Labels

- Reuse `.tabChipContentLayout()` and `.tabChipShell(...)` for editing variants or non-button inner content.
- Pass `showsCloseButton: false` to hide `x` while preserving the 36pt trailing reserve.
- Keep the private close button's hover behavior and optional `closeHelpText`; nil suppresses `.help` through `OptionalHelp`.
- Labels render through `AppMarkdownInlineLabel`, whose chips stay `.standard` across selection. Use `AppMarkdownInlineCodeChip(..., style:)` directly only for intentionally selection-aware surfaces.
