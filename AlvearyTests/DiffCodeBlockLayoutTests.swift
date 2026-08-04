import AppKit
import XCTest

@testable import Alveary

@MainActor
final class DiffCodeBlockLayoutTests: XCTestCase {
    private let source = """
    scripts/scroll-to-experience.js
    @@
     (function () {
    +    // Keep the experience shortcut inert when its target is not present.
         var btn = document.getElementById('scroll-to-experience');
    """

    /// An unbounded text container reports its own clamped width from `usedRect(for:)`, which made
    /// the block a document ten million points wide — it scrolled for miles past its last glyph.
    func testDiffBlockWidthComesFromItsWidestLine() {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let rows = DiffCodeHighlighting.rows(in: source)
        let metrics = AppKitDiffCodeBlockMetrics(rows: rows, font: font)
        let textWidth = AppKitDiffCodeBlockContent.attributedString(rows: rows, font: font).size().width

        let view = AppKitDiffCodeBlockView()
        view.configure(rows: rows, font: font)
        view.frame = NSRect(x: 0, y: 0, width: 900, height: 200)
        view.layoutSubtreeIfNeeded()

        let expected = metrics.contentLeading + textWidth + AppKitDiffCodeBlockMetrics.contentTrailingPadding
        XCTAssertEqual(view.intrinsicContentSize.width, ceil(expected), accuracy: 2)
    }

    /// A diff whose last line is empty — an added blank line — must still occupy a row. The layout
    /// manager keeps that final line as its extra fragment, outside line-fragment enumeration.
    func testADiffEndingInAnEmptyLineKeepsThatRow() {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let blank = AppKitDiffCodeBlockView()
        blank.configure(rows: DiffCodeHighlighting.rows(in: "@@\n keep\n+"), font: font)
        let filled = AppKitDiffCodeBlockView()
        filled.configure(rows: DiffCodeHighlighting.rows(in: "@@\n keep\n+x"), font: font)

        XCTAssertEqual(blank.intrinsicContentSize.height, filled.intrinsicContentSize.height)
    }

    /// The palette caches its swatches once, so they have to stay dynamic — a frozen resolution
    /// would keep painting the light gutter after the app switches to dark.
    func testDiffPaletteSwatchesStillResolvePerAppearance() {
        let wash = AppKitDiffCodeBlockPalette.gutterWash(for: .context)
        var light: NSColor?
        var dark: NSColor?
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance { light = wash.usingColorSpace(.sRGB) }
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance { dark = wash.usingColorSpace(.sRGB) }

        XCTAssertNotNil(light)
        XCTAssertNotEqual(light, dark)
    }

    /// Tool output renders its diff through the transcript code surface, whose scroll view never
    /// sizes a document view on its own.
    func testTranscriptToolOutputSizesItsDiffDocument() {
        let surface = AppKitTranscriptCodeSurfaceView()
        surface.configure(
            .highlighted(
                content: source,
                language: "diff",
                preservesLeadingLineNumberPrefixes: false,
                typography: TranscriptTypography()
            )
        )
        surface.frame = NSRect(x: 0, y: 0, width: 900, height: 200)
        surface.layoutSubtreeIfNeeded()

        let documentFrame = surface.subviews
            .compactMap { $0 as? NSScrollView }
            .first?
            .documentView?
            .frame
        XCTAssertEqual(documentFrame?.width, 900)
        XCTAssertEqual(documentFrame?.height, surface.intrinsicContentSize.height)
    }

    /// The block hugging its content is what keeps a diff that fits from scrolling at all.
    func testADiffNarrowerThanItsBlockDoesNotOverflow() {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        let block = AppKitMarkdownCodeBlockView(code: source, languageHint: "diff", codeFont: font)
        block.frame = NSRect(x: 0, y: 0, width: 900, height: 200)
        block.layoutSubtreeIfNeeded()

        let documentWidth = block.subviews
            .compactMap { $0 as? NSScrollView }
            .first?
            .documentView?
            .frame
            .width
        XCTAssertEqual(documentWidth, 900)
    }
}
