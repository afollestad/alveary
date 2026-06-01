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
