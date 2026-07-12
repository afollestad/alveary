import AppKit
import XCTest

@testable import Alveary

@MainActor
extension SidebarDragInteractionTests {
    func testAutoscrollVelocityUsesLinearEdgeBandsAndHorizontalGating() {
        let viewport = CGRect(x: 0, y: 0, width: 200, height: 200)

        XCTAssertEqual(sidebarAutoscrollVelocity(location: CGPoint(x: 100, y: 0), viewport: viewport), -12)
        XCTAssertEqual(sidebarAutoscrollVelocity(location: CGPoint(x: 100, y: 16), viewport: viewport), -6)
        XCTAssertEqual(sidebarAutoscrollVelocity(location: CGPoint(x: 100, y: 100), viewport: viewport), 0)
        XCTAssertEqual(sidebarAutoscrollVelocity(location: CGPoint(x: 100, y: 184), viewport: viewport), 6)
        XCTAssertEqual(sidebarAutoscrollVelocity(location: CGPoint(x: 100, y: 200), viewport: viewport), 12)
        XCTAssertEqual(sidebarAutoscrollVelocity(location: CGPoint(x: -1, y: 0), viewport: viewport), 0)
    }

    func testAutoscrollOriginUsesDocumentDirectionAndClampsToBounds() {
        let flippedScrollView = makeAutoscrollTestScrollView(
            documentHeight: 300,
            viewportHeight: 100,
            documentIsFlipped: true
        )
        let flippedContentView = flippedScrollView.contentView

        flippedContentView.scroll(to: NSPoint(x: 0, y: 4))
        XCTAssertEqual(sidebarAutoscrollOriginY(
            contentView: flippedContentView,
            velocity: -12,
            documentIsFlipped: flippedScrollView.documentView?.isFlipped == true
        ), 0)

        flippedContentView.scroll(to: NSPoint(x: 0, y: 196))
        XCTAssertEqual(sidebarAutoscrollOriginY(
            contentView: flippedContentView,
            velocity: 12,
            documentIsFlipped: flippedScrollView.documentView?.isFlipped == true
        ), 200)

        let nonFlippedScrollView = makeAutoscrollTestScrollView(
            documentHeight: 300,
            viewportHeight: 100,
            documentIsFlipped: false
        )
        let nonFlippedContentView = nonFlippedScrollView.contentView
        nonFlippedContentView.scroll(to: NSPoint(x: 0, y: 100))
        XCTAssertEqual(sidebarAutoscrollOriginY(
            contentView: nonFlippedContentView,
            velocity: 12,
            documentIsFlipped: nonFlippedScrollView.documentView?.isFlipped == true
        ), 88)
    }

    func testAutoscrollDoesNotCreateRangeForShortInsetDocument() {
        let scrollView = makeAutoscrollTestScrollView(
            documentHeight: 80,
            viewportHeight: 100,
            contentInsets: NSEdgeInsets(top: 12, left: 0, bottom: 8, right: 0),
            documentIsFlipped: true
        )
        let contentView = scrollView.contentView
        let documentIsFlipped = scrollView.documentView?.isFlipped == true

        XCTAssertEqual(contentView.bounds.origin.y, -12)
        XCTAssertEqual(sidebarAutoscrollOriginY(
            contentView: contentView,
            velocity: -12,
            documentIsFlipped: documentIsFlipped
        ), -12)
        XCTAssertEqual(sidebarAutoscrollOriginY(
            contentView: contentView,
            velocity: 12,
            documentIsFlipped: documentIsFlipped
        ), -12)
    }

    func testStaleAutoscrollTickDoesNotOwnReplacementSessionTimer() {
        let staleSessionID = UUID()
        let replacementSessionID = UUID()

        XCTAssertFalse(sidebarAutoscrollTickOwnsTimer(
            tickSessionID: staleSessionID,
            timerSessionID: replacementSessionID
        ))
        XCTAssertTrue(sidebarAutoscrollTickOwnsTimer(
            tickSessionID: replacementSessionID,
            timerSessionID: replacementSessionID
        ))
    }

    private func makeAutoscrollTestScrollView(
        documentHeight: CGFloat,
        viewportHeight: CGFloat,
        contentInsets: NSEdgeInsets = .init(),
        documentIsFlipped: Bool
    ) -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: viewportHeight))
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = contentInsets
        scrollView.documentView = SidebarAutoscrollTestDocumentView(
            frame: NSRect(x: 0, y: 0, width: 200, height: documentHeight),
            isFlipped: documentIsFlipped
        )
        scrollView.tile()
        scrollView.layoutSubtreeIfNeeded()
        return scrollView
    }
}

private final class SidebarAutoscrollTestDocumentView: NSView {
    private let flipsCoordinates: Bool

    override var isFlipped: Bool { flipsCoordinates }

    init(frame frameRect: NSRect, isFlipped: Bool) {
        flipsCoordinates = isFlipped
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        nil
    }
}
