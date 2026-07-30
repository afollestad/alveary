## Markdown Components

Rules for shared markdown semantics plus the SwiftUI and AppKit renderer entry points.

Narrower scopes:

- `Core/AGENTS.md`: parser, cache, shared model, NSColor palette tokens, and task state.
- `SwiftUI/AGENTS.md`: public SwiftUI entry points and inline labels.
- `SwiftUI/Rendering/AGENTS.md`: SwiftUI-only markdown block rendering, tables, and code highlighting.
- `AppKit/AGENTS.md`: AppKit markdown renderer internals.

## Renderer Contract

- **Put semantics in Core.** Markdown parsing, source preprocessing, task identity, link metadata, inline-code styles, and palette tokens must stay renderer-neutral.
- **Keep renderers platform-specific.** `SwiftUI/` and `AppKit/` decide layout and drawing only; they should consume the same `AppMarkdownDocument` and block runs.
- **Prevent drift.** New markdown behavior needs shared parser/model coverage plus renderer coverage for both SwiftUI and AppKit, unless one renderer explicitly does not support it yet.

## Inline Labels

- `SwiftUI/AppMarkdown.swift` owns the public SwiftUI entry point and shared SwiftUI typography environment.
- `Core/AppMarkdownParser.swift` owns Foundation markdown parsing, HTML/image preprocessing, and composer chip rewriting.
- `Core/AppMarkdownDocumentCache.swift` owns parsed document caching and task-list state namespaces.
- `SwiftUI/AppMarkdownInlineCodeChip.swift` owns compact single-line chip rendering.
- `SwiftUI/Rendering/` owns the SwiftUI block renderer internals.
- Use `AppMarkdownInlineLabel`, not raw `Text`, for single-line user strings that may contain inline code or `@file` mentions.
- Keep chip backgrounds clamped to the surrounding text line height so row/tab height stays uniform.
- Mention detection reuses `ChatComposerTextSupport.fileMentionMatches(in:)` plus `CanonicalPath.decodeStoredMentionPath(_:)`.
- Keep mentions inside fenced or inline-code ranges as code; do not re-chip them.
- Drive text and chip sizes from the single `textStyle` parameter.
- For explicit accessibility labels, use `AppMarkdownInlineLabel.plainText(from:)`. It strips backticks and decodes mentions without regex edge cases.

## Inline Code Palettes

- Inline-code chips have four styles:
    - `.standard`: neutral gray for unselected rows, tabs, and terminal chips.
    - `.assistantBubble`: neutral gray tuned for assistant chat bubbles.
    - `.composer`: accent-backed fill for live typing, slash commands, mentions, and queued messages.
    - `.userBubble`: gray tuned for accent-tinted user bubbles.
- `AppMarkdownInlineLabel` always renders `.standard`; selection must not recolor its chips.
- Tune swatches in `Core/AppMarkdown+Palette.swift`.
    - `.composer` fill aliases `AppAccentFill.primaryNSColor`.
    - `.composer` foreground is `.labelColor`.
    - SwiftUI `Color` wrappers live under `SwiftUI/`; do not import SwiftUI from `Core/`.
    - Retune by changing `AppAccentFill`, not by adding fixed duplicate swatches.
- Multi-line chat bubbles use local attributed-text inline-code styling, not `AppMarkdownInlineCodeChip`, so chip views do not inflate line height.
- Shared markdown defaults must stay neutral; transcript settings are injected through `AppMarkdownTypography`, not by reading `TranscriptTypography` in renderer internals.
- Do not reintroduce attachment-rendered inline code in `AppMarkdownParser.attributedString(for:)` unless line height stays uniform another way.
- SwiftUI `Link` renders system blue by default; explicitly apply `.foregroundStyle(Color.accentColor)` where links should match app accent.

## Shared Behavior

- SwiftUI markdown rendering uses `AppMarkdownRenderer` under `SwiftUI/Rendering/`.
- AppKit markdown rendering uses `AppKitMarkdownView` under `AppKit/`.
- Unknown fenced-code languages must render as plain monospaced code.
- Images alone on their line (or with local/relative sources) become `.image` document blocks; remote images sharing a line with text stay in the markdown fragments carrying `AppMarkdownInlineImageAttribute` on their alt-text run (mirrors BlockInputKit's split rule).
- Both renderers draw inline images once loaded: SwiftUI swaps the alt run for the bitmap in `AppMarkdownInlineText`, AppKit swaps it for a baseline-aligned `NSTextAttachment` in `AppKitMarkdownAttributedStringBuilder` (measurer and renderer must share one store or heights diverge); until the bitmap arrives both show the alt text. Image blocks render through `AppMarkdownImageBlockView` (SwiftUI) and `AppKitMarkdownImageBlockView` (AppKit, its own BlockInputKit loader); both center a status spinner in the placeholder while the load runs, and the SwiftUI view clips the bitmap *before* its max-size frame — the frame can be wider than the fitted image, and clipping the frame leaves the image's trailing corners square.
- All markdown image loads go through the shared `AppMarkdownImageStore` (`Core/`); snapshot hosts inject a preloaded store via the `\.appMarkdownImageStore` environment key so no test touches the network. Single-line label surfaces (`.inline` parsing mode) keep the plain alt-text fallback.
- **Image failures are retryable, not terminal.** `ImageState.failed` carries its timestamp: `ensureLoad` retries after the interval, and a failure schedules a couple of self-driven retries — remote images can start existing later (GitHub attachments stay session-gated until their embedding content propagates). On a failed direct fetch the store consults `remoteFallbackURLProvider` (wired to `GitHubAttachmentImageURLResolver` in `ContentView`) and retries once under the *original* cache key. `seedRemoteImage(source:fileURL:)` marks a source loaded from local bytes and writes the shared disk-cache entry; the key `default-v1|url|8192` is what the store, BlockInputKit editors, and the preview modal all derive, so one seed serves every surface — a drift in those constants silently unshares the cache (regression-covered in `AppMarkdownImageStoreTests`).
- Clicking a loaded SwiftUI image block routes through `\.appMarkdownImagePreviewAction` when a host injects one (the PR pane routes it into the app image preview modal); with no action injected it falls back to opening the resolved remote URL. The action's `Equatable` compares only its stable `id` — never the closure — so hosts can rebuild it every render without invalidating the markdown subtree.
- The parser supports a small HTML subset: `b`, `strong`, `i`, `em`, `u`, `p`, and `a`.
- Task-list markers (`[ ]`, `[x]`) render as interactive checkboxes with local cached state.

## Palette Internals

- Keep scheme-aware palette colors as cached `static let NSColor` values.
- Dynamic `NSColor` resolves per appearance at draw time.
- Do not reintroduce `(for: ColorScheme)` for cached attributed-string test values; fresh dynamic `NSColor` instances are not `==`.
- If palette colors depend on the accent, use `NSColor.accentDerived(transform:)`; see `../Accent/AGENTS.md`.
