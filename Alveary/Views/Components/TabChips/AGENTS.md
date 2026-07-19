## Shared Tab Chips

Rules for `SelectableTabChip.swift` and `TabChipButtonStyle.swift`.

- Use `TabChipButtonStyle(isSelected:)` for pill-shaped selection controls.
- Keep the whole capsule as the hit area; do not wrap only the label in a plain button.
- Put outer padding on the button content, not the chip HStack, so pressed fill covers the full capsule.
- Keep close buttons as trailing `ZStack` overlays with `focusEffectDisabled()`.
- `SelectableTabChip` is the shared shell for conversation tabs and terminal session chips.
- Build new tab/chip surfaces on `SelectableTabChip`; layer rename or context-menu affordances around it instead of forking structure.
- Compact filter chips without status or close affordances may use `TabChipButtonStyle` directly with symmetric label padding; do not force `SelectableTabChip`'s reserved slots into filter rows.
- Route rename VoiceOver actions through `renameAccessibilityAction:` so the action binds to the select button.
- Use `TabChipStatusIndicator.spinner(...)` / `TabChipStatusIndicatorView` for spinner states in the fixed 8x8 status slot; the spinner renders through the shared `StatusIndicatorSpinner`.
- Reuse `.tabChipContentLayout()` and `.tabChipShell(...)` for editing variants or non-button inner content.
- Pass `showsCloseButton: false` to hide `x` while preserving the 36pt trailing reserve.
- Keep the private close button's hover behavior and optional `closeHelpText`; nil suppresses `.help` through `OptionalHelp`.
- Labels render through `AppMarkdownInlineLabel`, whose chips stay `.standard` across selection. Use `AppMarkdownInlineCodeChip(..., style:)` directly only for intentionally selection-aware surfaces.
