## Accent Tokens

Rules for `AppAccentFill.swift` and `NSColor+AccentDerived.swift`.

- Change the app accent in `Assets.xcassets/AccentColor.colorset`; `project.yml` wires it through `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`.
- Do not replace the asset with root `.tint(...)`; `Color.accentColor` does not follow environment tint everywhere.
- Use `AppAccentFill.primary` / `.pressed` for prominent accent-backed chrome: primary buttons, user bubbles, selected rows, selected tabs, selected terminal chips, prompt headers, diff rows, scroll-to-latest, composer chips, queue chips, and selected badges.
- Use `NSColor(named: "AccentColor")` only when you need the asset color regardless of the user's system accent.
- Pair `AppAccentFill` fills with `.primary` / `NSColor.labelColor`. Destructive buttons are the exception: red fill, white foreground.
- Keep `AppAccentFill` fully opaque. Earlier alpha tints showed background content through floating UI.
- Prefer `AppAccentFill` over fresh `Color.accentColor.opacity(...)`; naive accent opacity is too saturated in light mode and washed out in dark mode.
- `NSColor.accentDerived(transform:)` is the canonical dynamic accent helper.
    - Resolve `NSColor.controlAccentColor` inside `performAsCurrentDrawingAppearance`.
    - Put light/dark branching inside the transform via `appearance.bestMatch(from: [.darkAqua, .aqua])`.
    - Do not blend or alpha-adjust the unresolved dynamic accent outside that block.
- When feeding Textual `DynamicColor`, flatten dynamic `NSColor` with `resolved(for:)` for `.aqua` and `.darkAqua`.
    - Use `AppMarkdown.dynamicColor(from:)` for markdown surfaces.
    - Avoid relying on `Color(nsColor:)` dynamic bridging for Textual.
    - Textual-rendered chips will not reflect system-accent changes until relaunch; that is acceptable.
- Keep both `Any Appearance` and `Dark` slots in `AccentColor.colorset`, even when values match.
