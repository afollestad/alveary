## SwiftUI Markdown

SwiftUI markdown entry points live here.

- **Preserve public names.** Keep `AppMarkdownText`, `DeferredAppMarkdownText`, and `AppMarkdownInlineLabel` available for non-transcript surfaces.
- **Use Core.** Do not duplicate parser, palette, task-state, or block-run behavior here.
- **Stay SwiftUI-owned.** Renderer layout belongs under `Rendering/`; AppKit transcript work belongs under sibling `../AppKit/`.
