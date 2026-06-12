@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptScrollContainerTests {
    func testConfigureRestoresVisibleAnchorThroughRowIDAlias() throws {
        let container = activityGroupingContainer(height: 120)
        container.configure(
            rows: [
                activityGroupingRow("first", height: 60),
                activityGroupingRow("raw", height: 100),
                activityGroupingRow("last", height: 200)
            ],
            preserveBottomIfFollowing: false
        )
        let rawFrame = try XCTUnwrap(container.rowFrame(for: "raw"))
        container.scrollContentView(toY: rawFrame.minY + 20)
        let anchor = try XCTUnwrap(container.captureVisibleAnchor())

        container.configure(
            rows: [
                activityGroupingRow("first", height: 60),
                activityGroupingRow("group", height: 130),
                activityGroupingRow("last", height: 200)
            ],
            rowIDAliases: ["raw": "group"],
            preserveBottomIfFollowing: false
        )

        let groupFrame = try XCTUnwrap(container.rowFrame(for: "group"))
        XCTAssertEqual(anchor.rowID, "raw")
        XCTAssertEqual(container.scrollOffsetY, groupFrame.minY + anchor.offsetWithinRow, accuracy: 0.5)
    }

    func testAnimatedTargetScrollUsesRowIDAlias() throws {
        let container = activityGroupingContainer(height: 120)
        container.configure(
            rows: [
                activityGroupingRow("first", height: 60),
                activityGroupingRow("group", height: 130),
                activityGroupingRow("last", height: 200)
            ],
            rowIDAliases: ["raw": "group"],
            preserveBottomIfFollowing: false
        )
        let groupFrame = try XCTUnwrap(container.rowFrame(for: "group"))
        let anchor = AppKitTranscriptVisibleAnchor(rowID: "raw", offsetWithinRow: 12, generation: 0)

        let targetY = container.targetScrollY(
            shouldRestoreBottom: false,
            visibleAnchor: anchor,
            targetDocumentHeight: container.documentHeight
        )

        XCTAssertEqual(targetY, groupFrame.minY + anchor.offsetWithinRow, accuracy: 0.5)
    }

    private func activityGroupingContainer(height: CGFloat) -> AppKitTranscriptScrollContainerView {
        let container = AppKitTranscriptScrollContainerView(frame: NSRect(x: 0, y: 0, width: 300, height: height))
        container.layoutSubtreeIfNeeded()
        return container
    }

    private func activityGroupingRow(_ id: String, height: CGFloat) -> AppKitTranscriptLayoutRow {
        AppKitTranscriptLayoutRow(id: id, view: ActivityGroupingFixedHeightRowView(height: height))
    }
}

private final class ActivityGroupingFixedHeightRowView: NSView {
    private let fixedHeight: CGFloat

    init(height: CGFloat) {
        fixedHeight = height
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: fixedHeight)
    }
}
