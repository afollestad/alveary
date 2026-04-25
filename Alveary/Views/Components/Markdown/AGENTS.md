## Markdown Components

Rules for `AppMarkdown*` and `AppMarkdownInlineLabel`.

## Inline Labels

- Use `AppMarkdownInlineLabel`, not raw `Text`, for single-line user strings that may contain inline code or `@file` mentions.
- Keep chip backgrounds clamped to the surrounding text line height so row/tab height stays uniform.
- Mention detection reuses `ChatInputFieldTextSupport.fileMentionMatches(in:)` plus `CanonicalPath.decodeStoredMentionPath(_:)`.
- Keep mentions inside fenced or inline-code ranges as code; do not re-chip them.
- Drive text and chip sizes from the single `textStyle` parameter.
- For explicit accessibility labels, use `AppMarkdownInlineLabel.plainText(from:)`. It strips backticks and decodes mentions without regex edge cases.

## Inline Code Palettes

- Inline-code chips have three styles:
    - `.standard`: neutral gray for assistant bubbles, unselected rows, tabs, and terminal chips.
    - `.composer`: accent-backed fill for live typing, slash commands, mentions, and queued messages.
    - `.userBubble`: gray tuned for accent-tinted user bubbles.
- `AppMarkdownInlineLabel` always renders `.standard`; selection must not recolor its chips.
- Tune swatches in `AppMarkdown+Palette.swift`.
    - `.composer` fill aliases `AppAccentFill.primaryNSColor`.
    - `.composer` foreground is `.labelColor`.
    - Retune by changing `AppAccentFill`, not by adding fixed duplicate swatches.
- Multi-line chat bubbles use Textual inline-code styling, not `AppMarkdownInlineCodeChip`, so attachment height does not change line height.
- Do not reintroduce attachment-rendered inline code in `AppMarkdownParser.attributedString(for:)` unless line height stays uniform another way.
- SwiftUI `Link` renders system blue by default; explicitly apply `.foregroundStyle(Color.accentColor)` where links should match app accent.

## Textual Ordering

- Do not apply `.textual.structuredTextStyle(.default)` with custom `.textual.inlineStyle(...)` or `.textual.codeBlockStyle(...)`.
- The default structured style overwrites later per-style environment values.
- Drop the structured style call; per-style keys already default correctly.

## Palette Internals

- Keep scheme-aware palette colors as cached `static let NSColor` values.
- Dynamic `NSColor` resolves per appearance at draw time.
- Do not reintroduce `(for: ColorScheme)` for cached attributed-string test values; fresh dynamic `NSColor` instances are not `==`.
- If palette colors depend on the accent, use `NSColor.accentDerived(transform:)`; see `../Accent/AGENTS.md`.
