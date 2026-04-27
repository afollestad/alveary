## Markdown Renderer

Rules for the SwiftUI-only markdown block renderer, tables, and code highlighting.

- **Keep it SwiftUI-only.** Do not import AppKit, JavaScriptCore, or WebKit in this folder.
- **Preserve content.** Unknown markdown structures and unknown fenced-code languages must fall back to readable text, never blank output.
- **Respect lazy lists.** Avoid renderer-owned geometry loops, AppKit bridges, and long-lived row state.
- **Cache task state.** Task-list checkboxes are interactive, but their state is local UI state keyed by document and source-order path.
- **Keep highlighting lightweight.** Syntax rules are regex-based scan aids, not full language parsers or Prism parity.
- **Render overflow internally.** Wide code blocks and tables should scroll horizontally inside the block instead of widening transcript rows.
- **Use concise comments.** Add comments only where parsing, block grouping, or run-range conversion is non-obvious.

File map:

- `AppMarkdownRenderer.swift`: parsed document entry point.
- `AppMarkdownBlockContent.swift`: block dispatch for headings, lists, quotes, rules, tables, and code.
- `AppMarkdownBlockRuns.swift`: PresentationIntent run grouping helpers.
- `AppMarkdownInlineText.swift`: inline text, link, and inline-code styling.
- `AppMarkdownCodeBlock.swift`: fenced-code chrome and syntax highlighting.
- `AppMarkdownList.swift`: ordered, unordered, nested, and task-list rendering.
- `AppMarkdownTable.swift`: transcript table layout.
- `AppMarkdownTaskCheckbox.swift`: interactive task checkbox and local state cache.
