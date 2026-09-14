@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptScrollContainerTests {
    func testWidthReflowPreservesVisibleRowAndOffset() throws {
        let container = geometryContainer()
        container.configure(rows: geometryRows(), preserveBottomIfFollowing: false)
        let originalFrame = try XCTUnwrap(container.rowFrame(for: "geometry-5"))
        container.scrollContentView(toY: originalFrame.minY + 12)
        let anchor = try XCTUnwrap(container.captureVisibleAnchor())
        var metrics: [ChatTranscriptScrollMetrics] = []
        container.onScrollMetricsChanged = { metrics.append($0) }

        container.frame.size.width = 180
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()

        let updatedFrame = try XCTUnwrap(container.rowFrame(for: anchor.rowID))
        XCTAssertGreaterThan(updatedFrame.height, originalFrame.height)
        XCTAssertEqual(container.scrollOffsetY, updatedFrame.minY + anchor.offsetWithinRow, accuracy: 0.5)
        XCTAssertFalse(metrics.isEmpty)
        XCTAssertTrue(metrics.allSatisfy { abs($0.offsetY - container.scrollOffsetY) <= 0.5 })
        XCTAssertTrue(metrics.allSatisfy { abs($0.contentHeight - container.documentHeight) <= 0.5 })
    }

    func testBatchedOpposingHeightChangesPreserveAnchorWithoutDocumentGrowth() throws {
        let container = geometryContainer()
        let contentWidth = container.bounds.width - transcriptScrollLeadingInset - transcriptScrollTrailingInset
        let rows = (0..<4).map { index in
            let view = GeometryWidthSensitiveRow()
            view.contentArea = contentWidth * 80
            return AppKitTranscriptLayoutRow(id: "paired-\(index)", view: view)
        }
        container.configure(rows: rows, preserveBottomIfFollowing: false)
        let secondFrame = try XCTUnwrap(container.rowFrame(for: "paired-1"))
        container.scrollContentView(toY: secondFrame.minY + 12)
        let documentHeight = container.documentHeight
        let first = try XCTUnwrap(rows[0].view as? GeometryWidthSensitiveRow)
        let second = try XCTUnwrap(rows[1].view as? GeometryWidthSensitiveRow)
        first.contentArea = contentWidth * 120
        second.contentArea = contentWidth * 40

        container.rowHeightsInvalidated(
            rowIDs: ["paired-0", "paired-1"], preserveBottomIfFollowing: false,
            forceBottomIfPreserving: false, animatesLayoutChanges: false
        )

        XCTAssertEqual(container.documentHeight, documentHeight, accuracy: 0.5)
        XCTAssertEqual(container.scrollOffsetY, secondFrame.minY + 40 + 12, accuracy: 0.5)
    }

    func testWidthReflowKeepsFollowingAtNewBottom() throws {
        let container = geometryContainer()
        container.configure(rows: geometryRows(), preserveBottomIfFollowing: true)
        container.scrollToBottom()
        let previousHeight = container.documentHeight

        container.frame.size.width = 180
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(container.documentHeight, previousHeight)
        XCTAssertEqual(container.visibleBottomY, container.documentHeight, accuracy: 0.5)
        XCTAssertEqual(container.scrollOffsetX, 0, accuracy: 0.5)
    }

    func testViewportGrowthClampsScrollOffsetAfterContentFits() {
        let container = geometryContainer()
        container.configure(rows: geometryRows(count: 3), preserveBottomIfFollowing: false)
        container.scrollToBottom()

        container.frame.size.height = 2_000
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()

        XCTAssertEqual(container.scrollOffsetY, 0, accuracy: 0.5)
        XCTAssertEqual(container.visibleBottomY, container.documentHeight, accuracy: 0.5)
    }

    func testReplacingLongContentWithEmptyRowsClearsScrollRange() {
        let container = geometryContainer()
        container.configure(rows: geometryRows(), preserveBottomIfFollowing: false)
        container.scrollToBottom()

        container.configure(rows: [], preserveBottomIfFollowing: false)

        XCTAssertNil(container.rowFrame(for: "geometry-5"))
        XCTAssertEqual(container.scrollOffsetY, 0, accuracy: 0.5)
        XCTAssertLessThan(container.documentHeight, container.bounds.height)
        XCTAssertEqual(container.transcriptDocumentView.bottomSpacerView.frame.maxY, container.documentHeight, accuracy: 0.5)
    }

    func testLoadingOverlayDoesNotBecomeDocumentContent() {
        let container = geometryContainer()
        container.configure(rows: geometryRows(count: 2), preserveBottomIfFollowing: false)
        let documentHeight = container.documentHeight
        var metricCount = 0
        container.onScrollMetricsChanged = { _ in metricCount += 1 }

        container.setIsLoading(true)
        container.layoutSubtreeIfNeeded()

        XCTAssertTrue(container.isLoadingForTesting)
        XCTAssertTrue(container.loadingIndicator.superview === container)
        XCTAssertEqual(container.documentHeight, documentHeight, accuracy: 0.5)
        XCTAssertEqual(metricCount, 0)

        container.setIsLoading(false)

        XCTAssertFalse(container.isLoadingForTesting)
        XCTAssertGreaterThan(metricCount, 0)
    }

    func testEmptyContainerPublishesReadinessOnlyAfterUsableWidth() {
        let container = AppKitTranscriptScrollContainerView(frame: .zero)
        var readyCount = 0
        container.onStableLayout = { readyCount += 1 }
        container.setIsLoading(true)
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(readyCount, 0)

        container.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(readyCount, 0)
        XCTAssertTrue(container.isLoadingForTesting)
        XCTAssertEqual(container.transcriptDocumentView.frame.width, 320, accuracy: 0.5)
    }

    func testStableLayoutCallbackCanSynchronouslyInstallAndScrollRows() throws {
        let container = AppKitTranscriptScrollContainerView(frame: CGRect(x: 0, y: 0, width: 0, height: 100))
        container.layoutSubtreeIfNeeded()
        var installedDocumentHeight: CGFloat?
        var didInstall = false
        container.onStableLayout = { [weak container] in
            guard let container, !didInstall else { return }
            didInstall = true
            container.configure(rows: geometryRows(), preserveBottomIfFollowing: true)
            installedDocumentHeight = container.documentHeight
            container.scrollToBottom()
        }

        container.frame.size.width = 320
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()

        XCTAssertTrue(didInstall)
        XCTAssertGreaterThan(try XCTUnwrap(installedDocumentHeight), container.bounds.height)
        XCTAssertEqual(try XCTUnwrap(installedDocumentHeight), container.documentHeight, accuracy: 0.5)
        XCTAssertEqual(container.visibleBottomY, container.documentHeight, accuracy: 0.5)
    }

    func testStableLayoutCallbackMeasuresHeightInvalidationBeforeFollowing() throws {
        let container = geometryContainer()
        let row = GeometryWidthSensitiveRow()
        container.configure(rows: [AppKitTranscriptLayoutRow(id: "growing", view: row)], preserveBottomIfFollowing: true)
        var invalidatedDocumentHeight: CGFloat?
        var didInvalidate = false
        container.onStableLayout = { [weak container] in
            guard let container, !didInvalidate else { return }
            didInvalidate = true
            row.contentArea = 96_000
            container.rowHeightInvalidated(
                rowID: "growing", preserveBottomIfFollowing: true, forceBottomIfPreserving: true, animatesLayoutChanges: false
            )
            invalidatedDocumentHeight = container.documentHeight
        }

        container.needsLayout = true
        container.layoutSubtreeIfNeeded()

        let frame = try XCTUnwrap(container.rowFrame(for: "growing"))
        XCTAssertTrue(didInvalidate)
        XCTAssertEqual(frame.height, ceil(96_000 / frame.width), accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(invalidatedDocumentHeight), container.documentHeight, accuracy: 0.5)
        XCTAssertEqual(container.visibleBottomY, container.documentHeight, accuracy: 0.5)
    }
}

@MainActor
private func geometryContainer() -> AppKitTranscriptScrollContainerView {
    let container = AppKitTranscriptScrollContainerView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
    container.layoutSubtreeIfNeeded()
    return container
}

@MainActor
private func geometryRows(count: Int = 12) -> [AppKitTranscriptLayoutRow] {
    (0..<count).map { AppKitTranscriptLayoutRow(id: "geometry-\($0)", view: GeometryWidthSensitiveRow()) }
}

private final class GeometryWidthSensitiveRow: NSView {
    var contentArea: CGFloat = 24_000

    override var fittingSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: ceil(contentArea / max(bounds.width, 1)))
    }
}
