import AppKit
import QuartzCore

// AppKit owns transcript scrolling because SwiftUI lazy-list recycling and
// measurement were not adequate for Alveary's variable-height rows at the time
// of writing; explicit frames let us preserve anchors through growth and prepends.
@MainActor
struct AppKitTranscriptLayoutRow {
    let id: String
    let view: NSView
}

@MainActor
struct AppKitTranscriptVisibleAnchor: Equatable {
    let rowID: String
    let offsetWithinRow: CGFloat
    let generation: Int
}

@MainActor
final class AppKitTranscriptScrollContainerView: NSView {
    private let scrollView = NSScrollView()
    private let transcriptDocumentView = AppKitTranscriptDocumentLayoutView()
    private(set) var paginationGeneration = 0
    var onScrollMetricsChanged: ((ChatTranscriptScrollMetrics) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUpScrollView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpScrollView()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        transcriptDocumentView.layoutRows(width: bounds.width)
        publishScrollMetrics()
    }

    func configure(
        rows: [AppKitTranscriptLayoutRow],
        dirtyRowIDs: Set<String> = [],
        preserveBottomIfFollowing: Bool
    ) {
        let shouldRestoreBottom = preserveBottomIfFollowing && isAtBottom
        let visibleAnchor = shouldRestoreBottom ? nil : captureVisibleAnchor()
        transcriptDocumentView.configure(rows: rows, dirtyRowIDs: dirtyRowIDs)
        needsLayout = true
        layoutSubtreeIfNeeded()
        restoreScrollPosition(shouldRestoreBottom: shouldRestoreBottom, visibleAnchor: visibleAnchor)
        publishScrollMetrics()
    }

    func rowHeightInvalidated(
        rowID: String? = nil,
        preserveBottomIfFollowing: Bool,
        animatesLayoutChanges: Bool = true
    ) {
        let shouldRestoreBottom = preserveBottomIfFollowing && isAtBottom
        let visibleAnchor = shouldRestoreBottom ? nil : captureVisibleAnchor()
        // Named invalidation is the hot path for streaming, expansion, and task
        // changes. The nil fallback stays available for callers that cannot safely
        // identify the changed row and therefore must force a conservative pass.
        // Rows can report a fresh height while the document is measuring them;
        // that feedback is satisfied by the active pass, and reentering here
        // creates staggered row animations.
        guard !transcriptDocumentView.isMeasuringRows else {
            return
        }
        if transcriptDocumentView.isApplyingFrameUpdates {
            DispatchQueue.main.async { [weak self] in
                self?.rowHeightInvalidated(
                    rowID: rowID,
                    preserveBottomIfFollowing: preserveBottomIfFollowing,
                    animatesLayoutChanges: animatesLayoutChanges
                )
            }
            return
        }
        if let rowID {
            transcriptDocumentView.markRowHeightDirty(rowID)
        } else {
            transcriptDocumentView.markAllRowHeightsDirty()
        }
        if animatesLayoutChanges {
            transcriptDocumentView.animateNextLayoutChange()
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
        restoreScrollPosition(shouldRestoreBottom: shouldRestoreBottom, visibleAnchor: visibleAnchor)
        publishScrollMetrics()
    }

    func captureVisibleAnchor() -> AppKitTranscriptVisibleAnchor? {
        let topY = scrollOffsetY
        guard let visibleRow = transcriptDocumentView.firstRow(atOrBelow: topY) else {
            return nil
        }
        return AppKitTranscriptVisibleAnchor(
            rowID: visibleRow.id,
            offsetWithinRow: max(0, topY - visibleRow.frame.minY),
            generation: paginationGeneration
        )
    }

    @discardableResult
    func restoreVisibleAnchor(_ anchor: AppKitTranscriptVisibleAnchor) -> Bool {
        guard anchor.generation == paginationGeneration,
              let rowFrame = transcriptDocumentView.rowFrame(for: anchor.rowID)
        else {
            return false
        }

        scroll(toY: rowFrame.minY + anchor.offsetWithinRow)
        return true
    }

    func noteUserScrolledDuringPagination() {
        paginationGeneration += 1
    }

    func scrollToBottom() {
        scroll(toY: max(0, transcriptDocumentView.frame.height - scrollView.contentView.bounds.height))
    }

    var scrollOffsetY: CGFloat {
        scrollView.contentView.bounds.minY
    }

    var scrollOffsetX: CGFloat {
        scrollView.contentView.bounds.minX
    }

    var visibleBottomY: CGFloat {
        scrollView.contentView.bounds.maxY
    }

    var documentHeight: CGFloat {
        transcriptDocumentView.frame.height
    }

    func rowFrame(for id: String) -> CGRect? {
        transcriptDocumentView.rowFrame(for: id)
    }

    private var isAtBottom: Bool {
        let distanceFromBottom = transcriptDocumentView.frame.height - scrollView.contentView.bounds.maxY
        return distanceFromBottom <= 1
    }

    private func setUpScrollView() {
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView = transcriptDocumentView
        addSubview(scrollView)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    private func scroll(toY proposedY: CGFloat) {
        let maxY = max(0, transcriptDocumentView.frame.height - scrollView.contentView.bounds.height)
        let clampedY = min(max(0, proposedY), maxY)
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: clampedY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        publishScrollMetrics()
    }

    private func restoreScrollPosition(
        shouldRestoreBottom: Bool,
        visibleAnchor: AppKitTranscriptVisibleAnchor?
    ) {
        if shouldRestoreBottom {
            scrollToBottom()
            return
        }
        // Non-following updates preserve the user's top visible row by identity plus
        // offset within that row, so prepends and height changes above the viewport
        // do not shift the content the user was reading.
        guard let visibleAnchor, restoreVisibleAnchor(visibleAnchor) else {
            clampScrollOffset()
            return
        }
    }

    private func clampScrollOffset() {
        scroll(toY: scrollOffsetY)
    }

    @objc
    private func contentBoundsDidChange() {
        if scrollView.contentView.bounds.minX != 0 {
            scrollView.contentView.scroll(to: CGPoint(x: 0, y: scrollOffsetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        publishScrollMetrics()
    }

    private func publishScrollMetrics() {
        onScrollMetricsChanged?(
            ChatTranscriptScrollMetrics(
                offsetY: scrollOffsetY,
                contentHeight: documentHeight,
                containerHeight: scrollView.contentView.bounds.height
            )
        )
    }
}

@MainActor
final class AppKitTranscriptDocumentLayoutView: NSView {
    private struct RowFrameUpdate {
        let view: NSView
        let frame: CGRect
        let previousFrame: CGRect?
    }

    private struct RowHeightMeasurement {
        let contentWidth: CGFloat
        let viewID: ObjectIdentifier
        let height: CGFloat
    }

    private struct RowCacheKey: Hashable {
        let id: String
        let viewID: ObjectIdentifier
    }

    private let topInset: CGFloat = 20
    private let bottomInset: CGFloat = 14
    private let rowSpacing: CGFloat = 12
    private var rows: [AppKitTranscriptLayoutRow] = []
    private var rowFramesByID: [String: CGRect] = [:]
    private var measuredHeightsByRowID: [String: RowHeightMeasurement] = [:]
    private var dirtyRowIDs: Set<String> = []
    private var lastContentWidth: CGFloat?
    private var shouldAnimateNextLayoutChange = false
    private(set) var isMeasuringRows = false
    private(set) var isApplyingFrameUpdates = false

    override var isFlipped: Bool { true }

    func configure(rows: [AppKitTranscriptLayoutRow], dirtyRowIDs externallyDirtyRowIDs: Set<String> = []) {
        let incomingKeys = rows.map(rowCacheKey(for:))
        let incomingKeySet = Set(incomingKeys)
        let incomingViews = Set(rows.map { ObjectIdentifier($0.view) })
        for existingView in subviews where !incomingViews.contains(ObjectIdentifier(existingView)) {
            existingView.removeFromSuperview()
        }

        self.rows = rows
        let liveRowIDs = Set(rows.map(\.id))
        dirtyRowIDs.formIntersection(liveRowIDs)
        measuredHeightsByRowID = measuredHeightsByRowID.filter { rowID, measurement in
            incomingKeySet.contains(RowCacheKey(id: rowID, viewID: measurement.viewID))
        }
        dirtyRowIDs.formUnion(externallyDirtyRowIDs.intersection(liveRowIDs))
        for row in rows where row.view.superview !== self {
            row.view.identifier = NSUserInterfaceItemIdentifier(row.id)
            addSubview(row.view)
            dirtyRowIDs.insert(row.id)
        }
    }

    override func layout() {
        super.layout()
        layoutRows(width: bounds.width)
    }

    func layoutRows(width: CGFloat) {
        guard !isMeasuringRows, !isApplyingFrameUpdates else {
            return
        }

        let contentWidth = max(0, width - transcriptScrollLeadingInset - transcriptScrollTrailingInset)
        if lastContentWidth.map({ abs($0 - contentWidth) > 0.5 }) ?? true {
            markAllRowHeightsDirty()
            lastContentWidth = contentWidth
        }
        var currentY = topInset
        let previousFramesByID = rowFramesByID
        rowFramesByID = [:]
        let shouldAnimate = shouldAnimateNextLayoutChange && window != nil
        shouldAnimateNextLayoutChange = false
        var frameUpdates: [RowFrameUpdate] = []

        isMeasuringRows = true
        do {
            defer { isMeasuringRows = false }
            for row in rows {
                let rowHeight = measuredHeight(for: row, contentWidth: contentWidth, currentY: currentY)
                let rowFrame = CGRect(
                    x: transcriptScrollLeadingInset,
                    y: currentY,
                    width: contentWidth,
                    height: rowHeight
                )
                frameUpdates.append(
                    RowFrameUpdate(
                        view: row.view,
                        frame: rowFrame,
                        previousFrame: previousFramesByID[row.id]
                    )
                )
                rowFramesByID[row.id] = rowFrame
                currentY += rowHeight + rowSpacing
            }
        }

        if !rows.isEmpty {
            currentY -= rowSpacing
        }
        currentY += bottomInset
        frame.size = CGSize(width: width, height: max(currentY, 0))
        applyFrameUpdates(frameUpdates, animated: shouldAnimate)
    }

    func markRowHeightDirty(_ rowID: String) {
        dirtyRowIDs.insert(rowID)
    }

    func markAllRowHeightsDirty() {
        dirtyRowIDs.formUnion(rows.map(\.id))
    }

    func animateNextLayoutChange() {
        shouldAnimateNextLayoutChange = true
    }

    func rowFrame(for id: String) -> CGRect? {
        rowFramesByID[id]
    }

    func firstRow(atOrBelow offsetY: CGFloat) -> (id: String, frame: CGRect)? {
        rows.lazy.compactMap { row -> (id: String, frame: CGRect)? in
            guard let frame = self.rowFramesByID[row.id], frame.maxY >= offsetY else {
                return nil
            }
            return (row.id, frame)
        }.first
    }

    private func measuredHeight(
        for row: AppKitTranscriptLayoutRow,
        contentWidth: CGFloat,
        currentY: CGFloat
    ) -> CGFloat {
        let viewID = ObjectIdentifier(row.view)
        if !dirtyRowIDs.contains(row.id),
           let measurement = measuredHeightsByRowID[row.id],
           measurement.viewID == viewID,
           abs(measurement.contentWidth - contentWidth) <= 0.5 {
            return measurement.height
        }

        // Width is committed before measuring because transcript rows wrap markdown,
        // tables, and code blocks against their current AppKit frame. Clean rows reuse
        // cached heights; every row still receives a fresh frame for anchor math.
        row.view.frame = CGRect(
            x: transcriptScrollLeadingInset,
            y: currentY,
            width: contentWidth,
            height: row.view.frame.height
        )
        row.view.needsLayout = true
        row.view.layoutSubtreeIfNeeded()
        let rowHeight = max(0, row.view.fittingSize.height)
        measuredHeightsByRowID[row.id] = RowHeightMeasurement(
            contentWidth: contentWidth,
            viewID: viewID,
            height: rowHeight
        )
        dirtyRowIDs.remove(row.id)
        return rowHeight
    }

    private func applyFrameUpdates(_ updates: [RowFrameUpdate], animated: Bool) {
        isApplyingFrameUpdates = true
        defer { isApplyingFrameUpdates = false }

        guard animated else {
            updates.forEach { $0.view.frame = $0.frame }
            return
        }

        let animatedUpdates = updates.filter { update in
            guard let previousFrame = update.previousFrame else {
                return false
            }
            return previousFrame.width > 0 &&
                previousFrame.height > 0 &&
                previousFrame != update.frame
        }
        let animatedViewIDs = Set(animatedUpdates.map { ObjectIdentifier($0.view) })
        let immediateUpdates = updates.filter { update in
            !animatedViewIDs.contains(ObjectIdentifier(update.view))
        }
        immediateUpdates.forEach { $0.view.frame = $0.frame }
        guard !animatedUpdates.isEmpty else {
            return
        }

        // Row height changes affect every subsequent row. A single transaction
        // keeps the resized row and all displaced rows moving on the same curve.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = appExpansionAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for update in animatedUpdates {
                if let previousFrame = update.previousFrame {
                    update.view.frame = previousFrame
                }
                update.view.animator().frame = update.frame
            }
        }
    }

    private func rowCacheKey(for row: AppKitTranscriptLayoutRow) -> RowCacheKey {
        RowCacheKey(id: row.id, viewID: ObjectIdentifier(row.view))
    }
}
