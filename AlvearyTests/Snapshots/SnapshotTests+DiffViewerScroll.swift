import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testDiffViewerStructuredDiffCreatesHorizontalScrollRangeForLongLines() throws {
        let rawDiff = Self.longLineStructuredDiff()
        let diff = try XCTUnwrap(DiffParser.parse(rawDiff).first)
        let host = DiffPreviewScrollHost(
            StructuredDiffPreview(diff: diff, rawDiffContent: rawDiff),
            size: CGSize(width: 260, height: 220)
        )
        defer { host.close() }

        let narrowScrollView = try host.scrollView()
        let narrowMaxX = try host.assertHorizontalOverflow(on: narrowScrollView)

        host.resize(to: CGSize(width: 900, height: 220))
        let wideScrollView = try host.scrollView()
        let wideMaxX = try host.horizontalMaxX(in: wideScrollView)
        XCTAssertLessThan(wideMaxX, narrowMaxX)
        XCTAssertLessThanOrEqual(wideScrollView.contentView.bounds.origin.x, wideMaxX + 0.5)

        host.resize(to: CGSize(width: 260, height: 220))
        let resizedNarrowScrollView = try host.scrollView()
        let resizedNarrowMaxX = try host.assertHorizontalOverflow(on: resizedNarrowScrollView)
        XCTAssertGreaterThan(resizedNarrowMaxX, wideMaxX)
    }

    func testDiffViewerRawFallbackCreatesHorizontalScrollRangeForLongLines() throws {
        let host = DiffPreviewScrollHost(
            RawDiffFallbackView(
                rawDiffContent: Self.longLineRawDiff(),
                note: "Showing the raw patch because the diff could not be parsed into hunks."
            ),
            size: CGSize(width: 260, height: 180)
        )
        defer { host.close() }

        _ = try host.assertHorizontalOverflow(on: try host.scrollView())
    }

    func testDiffViewerStructuredDiffDoesNotScrollWhenLinesFit() throws {
        let rawDiff = Self.shortLineStructuredDiff()
        let diff = try XCTUnwrap(DiffParser.parse(rawDiff).first)
        let host = DiffPreviewScrollHost(
            StructuredDiffPreview(diff: diff, rawDiffContent: rawDiff),
            size: CGSize(width: 600, height: 220)
        )
        defer { host.close() }

        // The retired 8pt-per-character estimate reserved scroll space no row
        // could fill, so a fitting diff still scrolled horizontally.
        let maxX = try host.horizontalMaxX(in: try host.scrollView())
        XCTAssertEqual(maxX, 0, accuracy: 0.5)
    }

    func testDiffViewerLongFilePathDoesNotWidenShortLineDiff() throws {
        let longPath = String(repeating: "nested-directory/", count: 12) + "file.js"
        let diff = try XCTUnwrap(DiffParser.parse(Self.tinyLineDiff(path: longPath)).first)
        let host = DiffPreviewScrollHost(
            FlattenedDiffPreview(files: [diff], showsFileHeaders: true),
            size: CGSize(width: 400, height: 220)
        )
        defer { host.close() }

        // The file header frames to the viewport width and truncates its path;
        // its untruncated ideal must not widen the scrollable area.
        let maxX = try host.horizontalMaxX(in: try host.scrollView())
        XCTAssertEqual(maxX, 0, accuracy: 0.5)
    }

    func testDiffViewerLongLineDiffStillScrollsWithFileHeaders() throws {
        let diff = try XCTUnwrap(DiffParser.parse(Self.longLineChangedDiff()).first)
        let host = DiffPreviewScrollHost(
            FlattenedDiffPreview(files: [diff], showsFileHeaders: true, allowsFileCollapse: true),
            size: CGSize(width: 320, height: 240)
        )
        defer { host.close() }

        // The file header frames to the viewport so its collapse caret stays on
        // the pane edge; that clamp must not shrink the scrollable area the
        // long line still needs.
        _ = try host.assertHorizontalOverflow(on: try host.scrollView())
    }

    func testDiffViewerFileHeaderPinsDuringHorizontalScroll() throws {
        let diff = try XCTUnwrap(DiffParser.parse(Self.longLineChangedDiff()).first)
        let host = DiffPreviewScrollHost(
            FlattenedDiffPreview(files: [diff], showsFileHeaders: true, allowsFileCollapse: true),
            size: CGSize(width: 420, height: 200)
        )
        defer { host.close() }

        let scrollView = try host.scrollView()
        let before = try host.fileHeaderBandPNG()
        _ = try host.assertHorizontalOverflow(on: scrollView)
        host.pumpRunLoop()

        // Scrolling right must leave the pinned header band pixel-identical:
        // the path, badges, and caret stay at the pane's leading edge while
        // the hunk rows below travel.
        let after = try host.fileHeaderBandPNG()
        XCTAssertFalse(before.isEmpty)
        XCTAssertEqual(before, after)
    }

    func testDiffViewerLongLineFileHeaderFitsPaneWidth() throws {
        let diff = try XCTUnwrap(DiffParser.parse(Self.longLineChangedDiff()).first)

        // The path, badges, and collapse caret must all stay inside the pane
        // even though the diff's lines scroll far past its trailing edge.
        assertMacSnapshot(
            FlattenedDiffPreview(files: [diff], showsFileHeaders: true, allowsFileCollapse: true),
            size: CGSize(width: 420, height: 200),
            named: "diff_viewer_long_line_file_header_fits_pane"
        )
    }

    private static func shortLineStructuredDiff() -> String {
        shortLineDiff(path: "scripts/scroll-to-experience.js")
    }

    private static func shortLineDiff(path: String) -> String {
        """
        diff --git a/\(path) b/\(path)
        --- a/\(path)
        +++ b/\(path)
        @@ -1,4 +1,5 @@
         (function () {
        +    // Keep the experience shortcut inert when its target is not present.
        """
    }

    private static func tinyLineDiff(path: String) -> String {
        """
        diff --git a/\(path) b/\(path)
        --- a/\(path)
        +++ b/\(path)
        @@ -1,2 +1,3 @@
         (function () {
        +    let ready = true;
        """
    }

    private static func longLineStructuredDiff() -> String {
        let longAttribute = String(repeating: "ceiling-thumbnail-segment-", count: 36)
        return """
        diff --git a/index.html b/index.html
        --- a/index.html
        +++ b/index.html
        @@ -449,7 +449,7 @@
                         class="column col-xs-12 col-sm-6 col-md-4 col-lg-3 col-xl-3 col-3 portfolio-image" />

                     <img
        -                    src="images/portfolio/cieling_thumbnail.jpg"
        +                    src="images/portfolio/\(longAttribute)ceiling_thumbnail.jpg"
                         loading="lazy"
                         decoding="async"
                         class="column col-xs-12 col-sm-6 col-md-4 col-lg-3 col-xl-3 col-3 portfolio-image" />
        """
    }

    /// A long line paired with real added/deleted lines, so the file header
    /// renders its `+N` / `-N` badges beside the path. `longLineStructuredDiff`
    /// cannot: its blank context line ends the hunk at the first line.
    private static func longLineChangedDiff() -> String {
        let longAttribute = String(repeating: "ceiling-thumbnail-segment-", count: 36)
        return """
        diff --git a/index.html b/index.html
        --- a/index.html
        +++ b/index.html
        @@ -449,2 +449,2 @@
             <img
        -            src="images/portfolio/cieling_thumbnail.jpg"
        +            src="images/portfolio/\(longAttribute)ceiling_thumbnail.jpg"
        """
    }

    private static func longLineRawDiff() -> String {
        let longLine = String(repeating: "raw-patch-segment-", count: 48)
        return """
        diff --git a/generated.log b/generated.log
        --- a/generated.log
        +++ b/generated.log
        +\(longLine)
        """
    }
}

@MainActor
private final class DiffPreviewScrollHost<Content: View> {
    private let controller: NSHostingController<AnyView>
    private let window: NSWindow

    init(
        _ view: Content,
        size: CGSize
    ) {
        let rootView = AnyView(
            view
                .transaction { $0.animation = nil }
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                .environment(\.layoutDirection, .leftToRight)
                .environment(\.colorScheme, ColorScheme.light)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        )

        controller = NSHostingController(rootView: rootView)
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.appearance = NSAppearance(named: .aqua)

        window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -size.width - 1200, y: -size.height - 1200), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .windowBackgroundColor
        window.contentViewController = controller
        window.makeFirstResponder(nil)
        layout()
    }

    func close() {
        window.close()
    }

    func resize(to size: CGSize) {
        window.setContentSize(size)
        controller.view.frame = CGRect(origin: .zero, size: size)
        layout()
    }

    func scrollView(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> NSScrollView {
        try XCTUnwrap(
            controller.view.diffPreviewDescendants(of: NSScrollView.self)
                .first { $0.documentView != nil && $0.contentView.bounds.width > 0 },
            file: file,
            line: line
        )
    }

    func horizontalMaxX(
        in scrollView: NSScrollView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> CGFloat {
        layout()
        let documentView = try XCTUnwrap(scrollView.documentView, file: file, line: line)
        return max(documentView.frame.width - scrollView.contentView.bounds.width, 0)
    }

    @discardableResult
    func assertHorizontalOverflow(
        on scrollView: NSScrollView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> CGFloat {
        layout()
        let documentView = try XCTUnwrap(scrollView.documentView, file: file, line: line)
        let visibleWidth = scrollView.contentView.bounds.width
        XCTAssertGreaterThan(documentView.frame.width, visibleWidth + 0.5, file: file, line: line)

        let maxX = max(documentView.frame.width - visibleWidth, 0)
        XCTAssertGreaterThan(maxX, 0.5, file: file, line: line)

        scrollView.contentView.scroll(to: NSPoint(x: maxX, y: scrollView.contentView.bounds.origin.y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        XCTAssertGreaterThan(scrollView.contentView.bounds.origin.x, 0.5, file: file, line: line)
        return maxX
    }

    /// Lets `onScrollGeometryChange` deliver its action after a programmatic
    /// scroll; the SwiftUI bridge dispatches it on a later run-loop turn.
    func pumpRunLoop(seconds: TimeInterval = 0.05) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        layout()
    }

    /// PNG of the top band covering the first file header (24pt clears the
    /// header's ~22pt row without reaching the hunk header ~33pt down).
    /// `CGImage.cropping` uses top-left image coordinates, so the crop is
    /// flip-proof regardless of the hosting view's coordinate orientation.
    func fileHeaderBandPNG(
        bandHeight: CGFloat = 24,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Data {
        layout()
        let view = controller.view
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds), file: file, line: line)
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = try XCTUnwrap(rep.cgImage, file: file, line: line)
        let scale = CGFloat(image.width) / view.bounds.width
        let band = try XCTUnwrap(
            image.cropping(to: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: bandHeight * scale)),
            file: file,
            line: line
        )
        let bandData = NSBitmapImageRep(cgImage: band).representation(using: .png, properties: [:])
        return try XCTUnwrap(bandData, file: file, line: line)
    }

    private func layout() {
        window.layoutIfNeeded()
        window.displayIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        controller.view.displayIfNeeded()
    }
}

private extension NSView {
    func diffPreviewDescendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        var matches = subviews.compactMap { $0 as? ViewType }
        for subview in subviews {
            matches.append(contentsOf: subview.diffPreviewDescendants(of: type))
        }
        return matches
    }
}
