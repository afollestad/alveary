@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptScrollContainerTests {
    func testHorizontalScrollIsClampedToZero() throws {
        let container = makeContainerForHorizontalScroll(height: 120)
        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: "first", view: FixedHorizontalHeightRowView(height: 80)),
                AppKitTranscriptLayoutRow(id: "second", view: FixedHorizontalHeightRowView(height: 80))
            ],
            preserveBottomIfFollowing: false
        )

        let scrollView = try XCTUnwrap(container.descendants(of: NSScrollView.self).first)
        scrollView.contentView.scroll(to: CGPoint(x: 24, y: 20))
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scrollView.contentView)

        XCTAssertEqual(container.scrollOffsetX, 0, accuracy: 0.5)
        XCTAssertEqual(container.scrollOffsetY, 20, accuracy: 0.5)
    }

    private func makeContainerForHorizontalScroll(height: CGFloat) -> AppKitTranscriptScrollContainerView {
        let container = AppKitTranscriptScrollContainerView(frame: NSRect(x: 0, y: 0, width: 300, height: height))
        container.layoutSubtreeIfNeeded()
        return container
    }
}

private final class FixedHorizontalHeightRowView: NSView {
    private let fixedHeight: CGFloat

    init(height: CGFloat) {
        fixedHeight = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: fixedHeight)
    }
}

private extension NSView {
    func descendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.descendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}
