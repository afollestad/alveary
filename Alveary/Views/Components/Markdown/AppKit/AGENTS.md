## AppKit Markdown

AppKit markdown rendering for transcript migration lives here.

- **Serve AppKit transcripts.** This renderer exists so variable-height transcript rows can report exact AppKit heights; SwiftUI lazy-list recycling and measurement were not adequate for Alveary's transcript UX at the time of writing.
- **Consume Core.** Render `AppMarkdownDocument` and shared block runs; do not parse markdown differently from SwiftUI.
- **Accept typography.** AppKit transcript callers should pass `AppKitMarkdownTypography`; do not read transcript settings inside markdown views.
- **Surface links.** AppKit markdown should emit link clicks through `onOpenLink`; transcript-specific URL resolution belongs to transcript callers.
- **Own link hover.** Selectable `NSTextView` content defaults to an I-beam cursor; keep link cursor rects and mouse-move hit testing in the markdown text view so rendered links show the pointing hand.
- **Mirror list semantics.** Parent list kind decides markers; unordered lists use bullets even when item runs carry ordinals.
- **Align list markers.** Ordered numbers and unordered bullets share secondary color and mirror SwiftUI marker widths.
- **Keep bullet insets stable.** Draw the AppKit bullet inside the marker column; do not pin it to the trailing edge.
- **Own height.** AppKit views that can change intrinsic height must invalidate themselves and call their height-invalidation handler.
- **Use shared AppKit primitives.** Views that cache dynamic `NSColor` values into layer `CGColor`s should use `Components/AppKit` helpers so theme changes do not require one-off appearance observers in each leaf view.
- **Size scroll documents explicitly.** Code blocks and tables use `NSScrollView` for horizontal overflow; keep their document views frame-sized from natural content so transcript height probes cannot collapse or stretch the rendered blocks.
- **Constrain table width.** Tables should hug natural width until they exceed the bubble cap; wide tables should scroll internally.
- **Reserve table scroller lanes.** Wide tables should reserve vertical space so the overlay bar stays below the last row.
- **Hug table chrome.** Draw rounded fill and border on a content-height inner chrome view, not the stretched outer measurement view.
- **Stay infrastructure until wired.** Do not route non-transcript markdown surfaces through AppKit unless explicitly requested.
- **Prefer parity tests.** New AppKit markdown behavior should be tested against the same parser/model fixtures used by SwiftUI.
