## AppKit Markdown

AppKit markdown rendering for transcript migration lives here.

- **Serve AppKit transcripts.** This renderer exists so variable-height transcript rows can report exact AppKit heights; SwiftUI lazy-list recycling and measurement were not adequate for Alveary's transcript UX at the time of writing.
- **Consume Core.** Render `AppMarkdownDocument` and shared block runs; do not parse markdown differently from SwiftUI.
- **Accept typography.** AppKit transcript callers should pass `AppKitMarkdownTypography`; do not read transcript settings inside markdown views.
- **Surface links.** AppKit markdown should emit link clicks through `onOpenLink`; transcript-specific URL resolution belongs to transcript callers.
- **Own link hover.** Selectable `NSTextView` content defaults to an I-beam cursor; keep link cursor rects and mouse-move hit testing in the markdown text view so rendered links show the pointing hand.
- **Forward vertical wheel events.** Selectable text views and horizontal overflow wrappers should pass mostly-vertical scroll-wheel events to the transcript scroll owner so trackpad/mouse momentum is not trapped inside markdown content.

### Lists

- **Mirror list semantics.** Parent list kind decides markers; unordered lists use bullets even when item runs carry ordinals.
- **Align list markers.** Ordered numbers and unordered bullets share secondary color and mirror SwiftUI marker widths.
- **Keep bullet insets stable.** Draw the AppKit bullet inside the marker column; do not pin it to the trailing edge.

### Measurement, Overflow, And Tables

- **Own height.** AppKit views that can change intrinsic height must invalidate themselves and call their height-invalidation handler.
- **A diff block draws its own gutter; only the code is text.** `AppKitDiffCodeBlockView` puts the line numbers, marker, and washes outside the text view, so they cannot be selected or copied and a row's fill spans the full width — `.backgroundColor` would stop at the last glyph. Rows align to the text view's line fragments, which is exact only because code blocks never wrap.
- **`AppKitDiffGutterPainter` owns those columns for every surface that draws them.** The review-proposal card stacks one view per line and paints each through it; a new gutter-drawing surface goes through it too rather than reimplementing the washes and hairline. Its rects are measured from the gutter's left edge, matching `AppKitDiffCodeBlockMetrics`' columns.
- **Share the diff block's metrics with the measurer.** `AppKitDiffCodeBlockMetrics` and `AppKitDiffCodeBlockContent` are what keep a measured diff and a drawn one agreeing on where the code starts.
- **Size unwrapped code from `AppKitMarkdownTextView.measuredContentWidth()`.** Its container is unbounded, so `usedRect(for:)` answers with that container's own clamped width — ten million points — and a document sized from it scrolls past the last glyph and always reserves a scroller lane.
- **Cache the diff block's line geometry and palette.** The transcript redraws on scroll, so re-running text layout — or rebuilding swatches from their SwiftUI tokens — costs O(lines) every frame. Only content and font invalidate the geometry; width cannot, because the text container is unbounded.
- **Use shared AppKit primitives.** Views that cache dynamic `NSColor` values into layer `CGColor`s should use `Components/AppKit` helpers so theme changes do not require one-off appearance observers in each leaf view.
- **Size scroll documents explicitly.** Code blocks and tables use `NSScrollView` for horizontal overflow; keep their document views frame-sized from natural content so transcript height probes cannot collapse or stretch the rendered blocks.
- **Constrain table width.** Tables should hug natural width until they exceed the bubble cap; wide tables should scroll internally.
- **Reserve table scroller lanes.** Wide tables should reserve vertical space so the overlay bar stays below the last row.
- **Hug table chrome.** Draw rounded fill and border on a content-height inner chrome view, not the stretched outer measurement view.
- **Keep measurer parity.** `AppKitMarkdownLayoutMeasurer` must mirror renderer spacing, marker widths, table/code sizing, typography, and overflow reserves; update parity tests with renderer layout changes.

### Images And Scope

- **Inline images are attachment swaps keyed to one store.** `AppKitMarkdownAttributedStringBuilder` replaces loaded `AppMarkdownInlineImageAttribute` runs with baseline-aligned `NSTextAttachment`s and kicks loads on the passed `AppMarkdownImageStore`; measurer, renderer, and `AppKitMarkdownView` must share that store instance or measured and drawn heights diverge. `AppKitMarkdownView` rebuilds on the store's state-change notification when the document references the loaded source. Tests must inject a stub store — the default `.shared` store loads over the network.
- **Stay infrastructure until wired.** Do not route non-transcript markdown surfaces through AppKit unless explicitly requested.
- **Prefer parity tests.** New AppKit markdown behavior should be tested against the same parser/model fixtures used by SwiftUI.
