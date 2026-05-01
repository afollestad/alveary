@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitTranscriptScrollContainerTests: XCTestCase {
    func testEagerLayoutStacksRowsAndSizesDocument() {
        let container = makeContainer(height: 200)

        container.configure(
            rows: [
                row("first", height: 40),
                row("second", height: 30),
                row("third", height: 20)
            ],
            preserveBottomIfFollowing: false
        )

        XCTAssertEqual(container.rowFrame(for: "first")?.minY, 20)
        XCTAssertEqual(container.rowFrame(for: "second")?.minY, 72)
        XCTAssertEqual(container.rowFrame(for: "third")?.minY, 114)
        XCTAssertEqual(container.documentHeight, 148)
    }

    func testAppendWhileFollowingKeepsBottomAnchored() {
        let container = makeContainer(height: 120)
        container.configure(
            rows: [
                row("first", height: 80),
                row("second", height: 80)
            ],
            preserveBottomIfFollowing: false
        )
        container.scrollToBottom()

        container.configure(
            rows: [
                row("first", height: 80),
                row("second", height: 80),
                row("third", height: 80)
            ],
            preserveBottomIfFollowing: true
        )

        XCTAssertEqual(container.visibleBottomY, container.documentHeight, accuracy: 0.5)
    }

    func testMeasuresRowsAfterApplyingContentWidth() throws {
        let container = makeContainer(height: 120)
        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: "wrapping", view: WidthDependentRowView())
            ],
            preserveBottomIfFollowing: false
        )

        let rowFrame = try XCTUnwrap(container.rowFrame(for: "wrapping"))
        XCTAssertEqual(rowFrame.height, 25.9, accuracy: 0.5)
    }

    func testPrependRestoresCapturedVisibleAnchorByRowIdentity() throws {
        let container = makeContainer(height: 120)
        container.configure(
            rows: [
                row("first", height: 80),
                row("second", height: 80),
                row("third", height: 80)
            ],
            preserveBottomIfFollowing: false
        )
        container.scrollToBottom()
        let anchor = try XCTUnwrap(container.captureVisibleAnchor())

        container.configure(
            rows: [
                row("prepended", height: 50),
                row("first", height: 80),
                row("second", height: 80),
                row("third", height: 80)
            ],
            preserveBottomIfFollowing: false
        )

        XCTAssertTrue(container.restoreVisibleAnchor(anchor))
        let firstFrame = try XCTUnwrap(container.rowFrame(for: anchor.rowID))
        XCTAssertEqual(container.scrollOffsetY, firstFrame.minY + anchor.offsetWithinRow, accuracy: 0.5)
    }

    func testConfigureAutomaticallyPreservesVisibleAnchorWhenNotFollowing() throws {
        let container = makeContainer(height: 120)
        container.configure(
            rows: [
                row("first", height: 80),
                row("second", height: 80),
                row("third", height: 80)
            ],
            preserveBottomIfFollowing: false
        )
        container.scrollToBottom()
        let anchor = try XCTUnwrap(container.captureVisibleAnchor())

        container.configure(
            rows: [
                row("prepended", height: 50),
                row("first", height: 80),
                row("second", height: 80),
                row("third", height: 80)
            ],
            preserveBottomIfFollowing: false
        )

        let restoredFrame = try XCTUnwrap(container.rowFrame(for: anchor.rowID))
        XCTAssertEqual(container.scrollOffsetY, restoredFrame.minY + anchor.offsetWithinRow, accuracy: 0.5)
    }

    func testRowHeightInvalidationPreservesVisibleAnchorWhenNotFollowing() throws {
        let container = makeContainer(height: 120)
        let first = MutableHeightRowView(height: 80)
        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: "first", view: first),
                row("second", height: 80),
                row("third", height: 80)
            ],
            preserveBottomIfFollowing: false
        )
        container.scrollToBottom()
        let anchor = try XCTUnwrap(container.captureVisibleAnchor())

        first.height = 130
        container.rowHeightInvalidated(preserveBottomIfFollowing: false)

        let restoredFrame = try XCTUnwrap(container.rowFrame(for: anchor.rowID))
        XCTAssertEqual(container.scrollOffsetY, restoredFrame.minY + anchor.offsetWithinRow, accuracy: 0.5)
    }

    func testNamedHeightInvalidationRemeasuresOnlyDirtyRow() throws {
        let container = makeContainer(height: 120)
        let first = MeasuringHeightRowView(height: 80)
        let second = MeasuringHeightRowView(height: 80)
        let third = MeasuringHeightRowView(height: 80)
        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: "first", view: first),
                AppKitTranscriptLayoutRow(id: "second", view: second),
                AppKitTranscriptLayoutRow(id: "third", view: third)
            ],
            preserveBottomIfFollowing: false
        )
        [first, second, third].forEach { $0.resetMeasurementCount() }

        first.height = 130
        container.rowHeightInvalidated(rowID: "first", preserveBottomIfFollowing: false)

        XCTAssertGreaterThan(first.measurementCount, 0)
        XCTAssertEqual(second.measurementCount, 0)
        XCTAssertEqual(third.measurementCount, 0)
        let firstFrame = try XCTUnwrap(container.rowFrame(for: "first"))
        let secondFrame = try XCTUnwrap(container.rowFrame(for: "second"))
        XCTAssertEqual(firstFrame.height, 130, accuracy: 0.5)
        XCTAssertEqual(secondFrame.minY, 162, accuracy: 0.5)
    }

    func testHeightInvalidationDuringMeasurementDoesNotReenterLayout() {
        let container = makeContainer(height: 120)
        let invalidating = LayoutInvalidatingRowView(height: 80)
        invalidating.onLayout = {
            container.rowHeightInvalidated(rowID: "first", preserveBottomIfFollowing: false)
        }

        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: "first", view: invalidating),
                row("second", height: 80)
            ],
            preserveBottomIfFollowing: false
        )

        XCTAssertEqual(invalidating.maximumObservedLayoutDepth, 1)
    }

    func testHeightInvalidationDuringFrameApplicationIsDeferred() throws {
        let container = makeContainer(height: 120)
        let invalidating = FrameInvalidatingRowView(height: 80)
        invalidating.onFirstFrameApplication = {
            invalidating.height = 120
            container.rowHeightInvalidated(rowID: "first", preserveBottomIfFollowing: false)
        }

        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: "first", view: invalidating),
                row("second", height: 80)
            ],
            preserveBottomIfFollowing: false
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        let firstFrame = try XCTUnwrap(container.rowFrame(for: "first"))
        let secondFrame = try XCTUnwrap(container.rowFrame(for: "second"))
        XCTAssertEqual(firstFrame.height, 120, accuracy: 0.5)
        XCTAssertEqual(secondFrame.minY, 152, accuracy: 0.5)
    }

    func testConfigureDirtyRowIDsRemeasuresOnlyDirtyRows() throws {
        let container = makeContainer(height: 120)
        let first = MeasuringHeightRowView(height: 80)
        let second = MeasuringHeightRowView(height: 80)
        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: "first", view: first),
                AppKitTranscriptLayoutRow(id: "second", view: second)
            ],
            preserveBottomIfFollowing: false
        )
        [first, second].forEach { $0.resetMeasurementCount() }

        second.height = 120
        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: "first", view: first),
                AppKitTranscriptLayoutRow(id: "second", view: second)
            ],
            dirtyRowIDs: ["second"],
            preserveBottomIfFollowing: false
        )

        XCTAssertEqual(first.measurementCount, 0)
        XCTAssertGreaterThan(second.measurementCount, 0)
        let secondFrame = try XCTUnwrap(container.rowFrame(for: "second"))
        XCTAssertEqual(secondFrame.height, 120, accuracy: 0.5)
    }

    func testAppendRemeasuresOnlyNewRows() {
        let container = makeContainer(height: 120)
        let first = MeasuringHeightRowView(height: 80)
        let second = MeasuringHeightRowView(height: 80)
        let third = MeasuringHeightRowView(height: 80)
        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: "first", view: first),
                AppKitTranscriptLayoutRow(id: "second", view: second)
            ],
            preserveBottomIfFollowing: false
        )
        [first, second, third].forEach { $0.resetMeasurementCount() }

        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: "first", view: first),
                AppKitTranscriptLayoutRow(id: "second", view: second),
                AppKitTranscriptLayoutRow(id: "third", view: third)
            ],
            preserveBottomIfFollowing: false
        )

        XCTAssertEqual(first.measurementCount, 0)
        XCTAssertEqual(second.measurementCount, 0)
        XCTAssertGreaterThan(third.measurementCount, 0)
    }

    func testFallbackHeightInvalidationRemeasuresAllRows() {
        let container = makeContainer(height: 120)
        let first = MeasuringHeightRowView(height: 80)
        let second = MeasuringHeightRowView(height: 80)
        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: "first", view: first),
                AppKitTranscriptLayoutRow(id: "second", view: second)
            ],
            preserveBottomIfFollowing: false
        )
        [first, second].forEach { $0.resetMeasurementCount() }

        container.rowHeightInvalidated(preserveBottomIfFollowing: false)

        XCTAssertGreaterThan(first.measurementCount, 0)
        XCTAssertGreaterThan(second.measurementCount, 0)
    }

    func testWidthChangeRemeasuresAllRows() {
        let container = makeContainer(height: 120)
        let first = MeasuringHeightRowView(height: 80)
        let second = MeasuringHeightRowView(height: 80)
        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: "first", view: first),
                AppKitTranscriptLayoutRow(id: "second", view: second)
            ],
            preserveBottomIfFollowing: false
        )
        [first, second].forEach { $0.resetMeasurementCount() }

        container.frame.size.width = 360
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(first.measurementCount, 0)
        XCTAssertGreaterThan(second.measurementCount, 0)
    }

    func testUserScrollDuringPaginationCancelsStaleAnchorRestore() throws {
        let container = makeContainer(height: 120)
        container.configure(
            rows: [
                row("first", height: 80),
                row("second", height: 80),
                row("third", height: 80)
            ],
            preserveBottomIfFollowing: false
        )
        container.scrollToBottom()
        let staleAnchor = try XCTUnwrap(container.captureVisibleAnchor())

        container.noteUserScrolledDuringPagination()
        let currentAnchor = try XCTUnwrap(container.captureVisibleAnchor())
        container.configure(
            rows: [
                row("prepended", height: 50),
                row("first", height: 80),
                row("second", height: 80),
                row("third", height: 80)
            ],
            preserveBottomIfFollowing: false
        )

        XCTAssertFalse(container.restoreVisibleAnchor(staleAnchor))
        let restoredFrame = try XCTUnwrap(container.rowFrame(for: currentAnchor.rowID))
        XCTAssertEqual(container.scrollOffsetY, restoredFrame.minY + currentAnchor.offsetWithinRow, accuracy: 0.5)
    }

    func testPublishesScrollMetricsAfterLayoutAndScroll() throws {
        let container = makeContainer(height: 120)
        var metrics: [ChatTranscriptScrollMetrics] = []
        container.onScrollMetricsChanged = { metrics.append($0) }

        container.configure(
            rows: [
                row("first", height: 80),
                row("second", height: 80),
                row("third", height: 80)
            ],
            preserveBottomIfFollowing: false
        )
        container.scrollToBottom()

        let lastMetrics = try XCTUnwrap(metrics.last)
        XCTAssertEqual(lastMetrics.offsetY, container.scrollOffsetY, accuracy: 0.5)
        XCTAssertEqual(lastMetrics.contentHeight, container.documentHeight, accuracy: 0.5)
        XCTAssertEqual(lastMetrics.containerHeight, 120, accuracy: 0.5)
        XCTAssertTrue(lastMetrics.isAtBottom)
    }

    private func makeContainer(height: CGFloat) -> AppKitTranscriptScrollContainerView {
        let container = AppKitTranscriptScrollContainerView(frame: NSRect(x: 0, y: 0, width: 300, height: height))
        container.layoutSubtreeIfNeeded()
        return container
    }

    private func row(_ id: String, height: CGFloat) -> AppKitTranscriptLayoutRow {
        AppKitTranscriptLayoutRow(id: id, view: FixedHeightRowView(height: height))
    }
}

private final class FixedHeightRowView: NSView {
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

private final class WidthDependentRowView: NSView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: frame.width / 10)
    }
}

private final class MutableHeightRowView: NSView {
    var height: CGFloat {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    init(height: CGFloat) {
        self.height = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: height)
    }
}

private final class MeasuringHeightRowView: NSView {
    var height: CGFloat {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    private(set) var measurementCount = 0

    init(height: CGFloat) {
        self.height = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var fittingSize: NSSize {
        measurementCount += 1
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    func resetMeasurementCount() {
        measurementCount = 0
    }
}

private final class LayoutInvalidatingRowView: NSView {
    let height: CGFloat
    var onLayout: (() -> Void)?
    private var currentLayoutDepth = 0
    private(set) var maximumObservedLayoutDepth = 0

    init(height: CGFloat) {
        self.height = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    override func layout() {
        currentLayoutDepth += 1
        maximumObservedLayoutDepth = max(maximumObservedLayoutDepth, currentLayoutDepth)
        onLayout?()
        currentLayoutDepth -= 1
        super.layout()
    }
}

private final class FrameInvalidatingRowView: NSView {
    var height: CGFloat {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }
    var onFirstFrameApplication: (() -> Void)?
    private var hasAppliedFirstFrame = false

    init(height: CGFloat) {
        self.height = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard !hasAppliedFirstFrame, newSize.height > 0 else {
            return
        }
        hasAppliedFirstFrame = true
        onFirstFrameApplication?()
    }
}
