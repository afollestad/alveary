## Markdown Core

Renderer-neutral markdown contracts live here.

- **Share semantics.** Parser preprocessing, `AppMarkdownDocument`, block-run grouping, task-list state, code-range parsing, renderer-neutral layout metrics, and NSColor palette tokens must stay usable by both SwiftUI and AppKit renderers.
- **Keep UI out.** Do not add SwiftUI or AppKit views in this folder; keep SwiftUI `Color` wrappers in `SwiftUI/`.
- **Test once.** Parser/model changes need core tests before renderer-specific tests.
- **Preserve fallbacks.** Unknown markdown and unknown fenced-code languages must preserve readable content.
- **Normalize code tails in core.** Use the shared code-display helper for SwiftUI and AppKit code/tool surfaces so trailing blank-line trimming stays renderer-neutral.
