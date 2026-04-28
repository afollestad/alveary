## Markdown Components

Rules for `AppMarkdown*`, `AppMarkdownInlineLabel`, palettes, and renderer entry points.

Narrower scopes:

- `Rendering/AGENTS.md`: SwiftUI-only markdown block rendering, tables, and code highlighting.

## Inline Labels

- `AppMarkdown.swift` owns the public SwiftUI entry point, inline-code style enum, and shared markdown typography environment.
- `AppMarkdownParser.swift` owns Foundation markdown parsing, HTML/image preprocessing, and composer chip rewriting.
- `AppMarkdownDocumentCache.swift` owns parsed document caching and task-list state namespaces.
- `AppMarkdownInlineCodeChip.swift` owns compact single-line chip rendering.
- `Rendering/` owns the SwiftUI block renderer internals.
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
- Multi-line chat bubbles use local attributed-text inline-code styling, not `AppMarkdownInlineCodeChip`, so chip views do not inflate line height.
- Shared markdown defaults must stay neutral; transcript settings are injected through `AppMarkdownTypography`, not by reading `TranscriptTypography` in renderer internals.
- Do not reintroduce attachment-rendered inline code in `AppMarkdownParser.attributedString(for:)` unless line height stays uniform another way.
- SwiftUI `Link` renders system blue by default; explicitly apply `.foregroundStyle(Color.accentColor)` where links should match app accent.

## Renderer Internals

- Markdown rendering uses `AppMarkdownRenderer` under `Rendering/`.
- Unknown fenced-code languages must render as plain monospaced code.
- Image markdown degrades to alt/link text; do not add image loading unless the product scope changes.
- The parser supports a small HTML subset: `b`, `strong`, `i`, `em`, `u`, `p`, and `a`.
- Task-list markers (`[ ]`, `[x]`) render as interactive checkboxes with local cached state.

## Palette Internals

- Keep scheme-aware palette colors as cached `static let NSColor` values.
- Dynamic `NSColor` resolves per appearance at draw time.
- Do not reintroduce `(for: ColorScheme)` for cached attributed-string test values; fresh dynamic `NSColor` instances are not `==`.
- If palette colors depend on the accent, use `NSColor.accentDerived(transform:)`; see `../Accent/AGENTS.md`.
