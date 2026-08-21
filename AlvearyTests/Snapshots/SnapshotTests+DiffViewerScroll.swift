import AppKit
import CoreGraphics
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

    /// A portrait screenshot must not set the row's height from its own pixels.
    ///
    /// The row sits in a vertical scroll view, which proposes unbounded height, so a `.fit` image
    /// answers with its intrinsic size — a 1170x2532 phone screenshot produced a 2532pt row.
    func testDiffViewerPortraitImageDoesNotStretchTheRow() throws {
        let host = DiffPreviewScrollHost(
            Self.portraitImageDiffPreview(),
            size: CGSize(width: 1_200, height: 700)
        )
        defer { host.close() }
        host.pumpRunLoop(seconds: 0.3)

        let scrollView = try host.scrollView()
        assertRowHeightComesFromThePaneNotTheImage(scrollView)
    }

    /// The same row at a pane too narrow for the image, where an unbounded row also scrolls sideways.
    func testDiffViewerPortraitImageFitsANarrowPane() throws {
        let host = DiffPreviewScrollHost(
            Self.portraitImageDiffPreview(),
            size: CGSize(width: 600, height: 700)
        )
        defer { host.close() }
        host.pumpRunLoop(seconds: 0.3)

        let scrollView = try host.scrollView()
        assertRowHeightComesFromThePaneNotTheImage(scrollView)
        let maxX = try host.horizontalMaxX(in: scrollView)
        XCTAssertEqual(maxX, 0, accuracy: 0.5)
    }

    /// An image row reports no scrollable width, so per this scope's rule it must clamp itself to the
    /// viewport rather than stretching to the width some *other* row's long line opened up.
    func testDiffViewerImageDoesNotStretchToAnotherRowsScrollWidth() throws {
        let host = DiffPreviewScrollHost(
            Self.portraitImageDiffPreview(includingLongLineFile: true),
            size: CGSize(width: 600, height: 700)
        )
        defer { host.close() }
        host.pumpRunLoop(seconds: 0.3)

        let scrollView = try host.scrollView()
        // The long line legitimately opens horizontal range...
        let maxX = try host.horizontalMaxX(in: scrollView)
        XCTAssertGreaterThan(maxX, 0)
        // ...but the image row must not have grown into it.
        assertRowHeightComesFromThePaneNotTheImage(scrollView)
    }

    /// The content is bounded by the pane rather than by the image, so the document view settles
    /// near the viewport instead of scaling with the image's 2532pt height (it measured 3315pt at a
    /// 1200pt pane and 1692pt at 600pt before the row was given a definite box).
    private func assertRowHeightComesFromThePaneNotTheImage(
        _ scrollView: NSScrollView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let documentHeight = scrollView.documentView?.frame.height ?? 0
        XCTAssertLessThan(
            documentHeight,
            scrollView.contentView.bounds.height + 200,
            "Row height must come from the pane, not the image",
            file: file,
            line: line
        )
    }

    private static func portraitImageDiffPreview(includingLongLineFile: Bool = false) -> some View {
        let path = "snapshots/LOCAL_CASH_happy.png"
        var raw = """
        diff --git a/\(path) b/\(path)
        deleted file mode 100644
        index abbe130..0000000
        Binary files a/\(path) and /dev/null differ
        """
        if includingLongLineFile {
            raw += "\n" + longLineChangedDiff()
        }
        let files = DiffParser.parse(raw)
        let fileID = FlattenedDiffPreviewRows.fileCollapseID(for: files[0], fileIndex: 0)
        let preview = DiffImagePreview(
            old: portraitImageVersion(path: path),
            new: nil
        )
        return FlattenedDiffPreview(
            files: files,
            imagePreviews: [fileID: preview],
            showsFileHeaders: true,
            loadImage: { _, _ in try portraitImageOutput() },
            openImage: { _ in }
        )
    }

    private static func portraitImageVersion(path: String) -> DiffImageVersion {
        DiffImageVersion(
            source: .git(.head(path: path)),
            side: .old,
            identityPrefix: "abc123",
            fileIdentity: path,
            fileExtension: "png",
            needsContentHash: false
        )
    }

    /// A phone screenshot's proportions, which is the shape that exposed the bug.
    private static func portraitImageOutput() throws -> DiffImagePreviewOutput {
        let width = 1_170
        let height = 2_532
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        return DiffImagePreviewOutput(image: image, pixelSize: CGSize(width: width, height: height))
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

/// Hosts a diff preview in a real window and reaches the `NSScrollView` behind it, which is the
/// only place the scroll view's content size can be read. Shared with `SnapshotTests+DiffViewerContentHeight`.
@MainActor
final class DiffPreviewScrollHost<Content: View> {
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

    func verticalMaxY(
        in scrollView: NSScrollView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> CGFloat {
        layout()
        let documentView = try XCTUnwrap(scrollView.documentView, file: file, line: line)
        return max(documentView.frame.height - scrollView.contentView.bounds.height, 0)
    }

    /// Scrolls to the bottom and pumps, so a caller can compare the content height
    /// the stack reported before every row on the way down was realized against the
    /// height it reports after.
    @discardableResult
    func scrollToBottom(
        _ scrollView: NSScrollView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> CGFloat {
        let maxY = try verticalMaxY(in: scrollView, file: file, line: line)
        scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: maxY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        pumpRunLoop()
        return maxY
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
