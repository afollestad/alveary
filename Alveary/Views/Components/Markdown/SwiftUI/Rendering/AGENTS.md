## Markdown Renderer

Rules for the SwiftUI-only markdown block renderer, tables, and code highlighting.

- **Keep it SwiftUI-only.** Do not import AppKit, JavaScriptCore, or WebKit in this folder; AppKit markdown lives in sibling `../../AppKit/`.
- **Preserve content.** Unknown markdown structures and unknown fenced-code languages must fall back to readable text, never blank output.
- **Respect lazy lists.** Avoid renderer-owned geometry loops, AppKit bridges, and long-lived row state.
- **Cache task state.** Task-list checkboxes are interactive, but their state is local UI state keyed by document and source-order path.
- **Keep highlighting lightweight.** Syntax rules are regex-based scan aids, not full language parsers or Prism parity.
- **Render overflow internally.** Wide code blocks and tables should scroll horizontally inside the block instead of exceeding transcript row bounds.
- **Measure code blocks by intrinsic width.** Fenced code may widen the markdown bubble up to the available cap, then scroll horizontally; thematic breaks stay width-neutral and only fill the width chosen by other blocks.
- **Cache repeated layout measurements.** Reuse exact-width block measurements and proposal-independent code/table measurements across size and placement passes; reset typed layout caches when subviews change.
- **Use markdown typography.** Body text inherits the caller's root font; explicit renderer variants must use `appMarkdownFont(...)`, never raw `.font(...)`. Transcript surfaces inject settings-backed `AppMarkdownTypography`.
- **Use concise comments.** Add comments only where parsing, block grouping, or run-range conversion is non-obvious.

File map:

- `AppMarkdownRenderer.swift`: parsed document entry point.
- `AppMarkdownBlockContent.swift`: block dispatch for headings, lists, quotes, rules, tables, and code.
- `AppMarkdownInlineText.swift`: inline text, link, and inline-code styling.
- `AppMarkdownCodeBlock.swift`: fenced-code chrome and syntax highlighting.
- `AppMarkdownList.swift`: ordered, unordered, nested, and task-list rendering.
- `AppMarkdownTable.swift`: transcript table layout.
- `AppMarkdownTaskCheckbox.swift`: interactive task checkbox view; shared task state lives in `../../Core/`.
