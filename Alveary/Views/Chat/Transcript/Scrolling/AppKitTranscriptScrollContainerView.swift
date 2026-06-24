import AppKit
import QuartzCore

@MainActor
final class AppKitTranscriptScrollContainerView: NSView {
    let scrollView = NSScrollView()
    let transcriptDocumentView = AppKitTranscriptDocumentLayoutView()
    var activeScrollAnimationToken: UUID?
    private(set) var paginationGeneration = 0
    var onScrollMetricsChanged: ((ChatTranscriptScrollMetrics) -> Void)?
    var shouldForceBottomAfterCurrentMeasurement = false
    private var rowIDAliases: [String: String] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUpScrollView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpScrollView()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        transcriptDocumentView.layoutRows(width: bounds.width)
        if restoreForcedBottomAfterMeasurementIfNeeded() {
            return
        }
        hydrateViewportRows()
        publishScrollMetrics()
    }

    func configure(
        rows: [AppKitTranscriptLayoutRow],
        dirtyRowIDs: Set<String> = [],
        rowIDAliases: [String: String] = [:],
        preserveBottomIfFollowing: Bool
    ) {
        let shouldRestoreBottom = preserveBottomIfFollowing && isAtBottom
        let visibleAnchor = captureVisibleAnchor()
        self.rowIDAliases = rowIDAliases
        transcriptDocumentView.configure(rows: rows, dirtyRowIDs: Set(dirtyRowIDs.map(canonicalRowID(for:))))
        needsLayout = true
        layoutSubtreeIfNeeded()
        restoreScrollPosition(shouldRestoreBottom: shouldRestoreBottom, visibleAnchor: visibleAnchor)
        hydrateViewportRows()
        publishScrollMetrics()
    }

    func rowHeightInvalidated(
        rowID: String? = nil,
        preserveBottomIfFollowing: Bool,
        forceBottomIfPreserving: Bool = false,
        animatesLayoutChanges: Bool = true
    ) {
        let shouldRestoreBottom = preserveBottomIfFollowing && (isAtBottom || forceBottomIfPreserving)
        let visibleAnchor = captureVisibleAnchor()
        let documentHeightBeforeLayout = documentHeight
        // Named invalidation is the hot path; nil stays available when callers
        // cannot identify the changed row. Reentrant measurement feedback is
        // satisfied by the active pass to avoid staggered row animations.
        if deferHeightInvalidationUntilStable(
            rowID: rowID,
            preserveBottomIfFollowing: preserveBottomIfFollowing,
            forceBottomIfPreserving: forceBottomIfPreserving,
            animatesLayoutChanges: animatesLayoutChanges,
            shouldRestoreBottom: shouldRestoreBottom
        ) {
            return
        }
        if let rowID {
            transcriptDocumentView.markRowHeightDirty(canonicalRowID(for: rowID))
        } else {
            transcriptDocumentView.markAllRowHeightsDirty()
        }
        if animatesLayoutChanges {
            transcriptDocumentView.animateNextLayoutChange()
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
        if restoreForcedBottomAfterMeasurementIfNeeded() {
            return
        }
        // A named dirty row can remeasure to the same frame; in that hot path
        // downstream frames and visible anchors are already stable.
        guard rowID == nil || transcriptDocumentView.lastLayoutChangedFrames else {
            hydrateViewportRows()
            publishScrollMetrics()
            return
        }
        if finishAnimatedHeightInvalidationIfNeeded(
            animatesLayoutChanges: animatesLayoutChanges,
            documentHeightBeforeLayout: documentHeightBeforeLayout,
            shouldRestoreBottom: shouldRestoreBottom,
            visibleAnchor: visibleAnchor
        ) {
            return
        }

        finishHeightInvalidationScrollUpdate(restoresPosition: true, shouldRestoreBottom: shouldRestoreBottom, visibleAnchor: visibleAnchor)
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
              let rowFrame = rowFrame(for: anchor.rowID)
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
        scroll(toY: .greatestFiniteMagnitude)
    }

    @discardableResult
    func scrollToRowTop(rowID: String, topInset: CGFloat = 0) -> Bool {
        guard let rowFrame = rowFrame(for: rowID) else {
            return false
        }
        scroll(toY: rowFrame.minY - topInset)
        return true
    }

    var scrollOffsetY: CGFloat { scrollView.contentView.bounds.minY }

    var scrollOffsetX: CGFloat { scrollView.contentView.bounds.minX }

    var visibleBottomY: CGFloat {
        let rawBottomY = scrollView.contentView.bounds.maxY
        let scrollableBottomY = transcriptDocumentView.scrollableContentBottomY
        return rawBottomY >= scrollableBottomY - 0.5 ? documentHeight : rawBottomY
    }

    var documentHeight: CGFloat { transcriptDocumentView.frame.height }

    func rowFrame(for id: String) -> CGRect? {
        // Raw `ChatItem` row IDs can collapse into an activity group, so external
        // row lookups stay on this path to follow the visual row after grouping.
        transcriptDocumentView.rowFrame(for: canonicalRowID(for: id))
    }

    private func canonicalRowID(for rowID: String) -> String {
        rowIDAliases[rowID] ?? rowID
    }

    private var isAtBottom: Bool {
        let distanceFromBottom = documentHeight - visibleBottomY
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
        scrollContentView(toY: proposedY)
        let hydratedCount = hydrateViewportRows()
        if hydratedCount > 0 {
            scrollContentView(toY: proposedY)
        }
        publishScrollMetrics()
    }

    func scrollContentView(toY proposedY: CGFloat) {
        let maxY = max(0, transcriptDocumentView.frame.height - scrollView.contentView.bounds.height)
        let clampedY = min(max(0, proposedY), maxY)
        scrollView.contentView.setBoundsOrigin(CGPoint(x: 0, y: clampedY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        scrollView.contentView.setBoundsOrigin(CGPoint(x: 0, y: clampedY))
    }

    func restoreScrollPosition(
        shouldRestoreBottom: Bool,
        visibleAnchor: AppKitTranscriptVisibleAnchor?
    ) {
        if shouldRestoreBottom {
            scrollToBottom()
            return
        }
        // Non-following updates preserve the user's top visible row by identity
        // plus offset so prepends and height changes above it do not shift reading.
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
        hydrateViewportRows()
        publishScrollMetrics()
    }

    @discardableResult
    func hydrateViewportRows() -> Int {
        let visibleRect = scrollView.contentView.bounds
        let prefetchMargin = visibleRect.height * 1.5
        let hydrationRect = visibleRect.insetBy(dx: 0, dy: -prefetchMargin)
        let documentHeightBeforeHydration = documentHeight
        let hydratedCount = transcriptDocumentView.hydrateRows(intersecting: hydrationRect)
        assert(abs(documentHeight - documentHeightBeforeHydration) <= 0.5, "Viewport hydration changed transcript document height")
        return hydratedCount
    }

    func publishScrollMetrics() {
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
    struct RowFrameUpdate {
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
    let bottomSpacerView = NSView()
    private var rows: [AppKitTranscriptLayoutRow] = []
    private var rowFramesByID: [String: CGRect] = [:]
    private var measuredHeightsByRowID: [String: RowHeightMeasurement] = [:]
    private var dirtyRowIDs: Set<String> = []
    private var lastContentWidth: CGFloat?
    private var shouldAnimateNextLayoutChange = false
    var exitingThoughtViewIDs: Set<ObjectIdentifier> = []
    var activeFrameAnimationCompletions: [() -> Void] = []
    var activeFrameAnimationTargetDocumentSize: CGSize?
    private(set) var isMeasuringRows = false
    var isApplyingFrameUpdates = false
    var hasActiveFrameAnimation = false
    private(set) var lastLayoutChangedFrames = false

    override var isFlipped: Bool { true }

    var scrollableContentBottomY: CGFloat { rowFramesByID.values.map(\.maxY).max() ?? 0 }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(bottomSpacerView)
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addSubview(bottomSpacerView)
    }

    func configure(rows: [AppKitTranscriptLayoutRow], dirtyRowIDs externallyDirtyRowIDs: Set<String> = []) {
        let incomingKeys = rows.map(rowCacheKey(for:))
        let incomingKeySet = Set(incomingKeys)
        let incomingViews = Set(rows.map { ObjectIdentifier($0.view) })
        let animatesThoughtRemoval = subviews.contains { existingView in
            existingView !== bottomSpacerView &&
                !incomingViews.contains(ObjectIdentifier(existingView)) &&
                canAnimateRemovedThoughtView(existingView)
        }
        for existingView in subviews where existingView !== bottomSpacerView && !incomingViews.contains(ObjectIdentifier(existingView)) {
            removeObsoleteView(existingView)
        }
        if animatesThoughtRemoval {
            animateNextLayoutChange()
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
        // Reentrant layout during a measured frame animation must not commit the
        // final document height early, or bottom-pinned collapse visibly jumps.
        guard !isMeasuringRows, !isApplyingFrameUpdates, !hasActiveFrameAnimation else {
            return
        }

        let contentWidth = max(0, width - transcriptScrollLeadingInset - transcriptScrollTrailingInset)
        lastLayoutChangedFrames = false
        if lastContentWidth.map({ abs($0 - contentWidth) > 0.5 }) ?? true {
            markAllRowHeightsDirty()
            lastContentWidth = contentWidth
        }
        let previousFramesByID = rowFramesByID
        rowFramesByID = [:]
        let shouldAnimate = shouldAnimateNextLayoutChange && window != nil
        shouldAnimateNextLayoutChange = false
        let measuredLayout = measuredRowLayout(contentWidth: contentWidth, previousFramesByID: previousFramesByID)
        let newDocumentHeight = max(measuredLayout.documentHeight, 0)
        // Skip unchanged frame sets so configuration echoes do not perturb anchors.
        lastLayoutChangedFrames = hasLayoutChanges(
            frameUpdates: measuredLayout.frameUpdates,
            documentWidth: width,
            documentHeight: newDocumentHeight
        )
        let targetDocumentSize = CGSize(width: width, height: newDocumentHeight)
        let shouldHoldShrinkingDocumentHeight = shouldAnimate && newDocumentHeight < frame.height - 0.5
        let appliedDocumentHeight = shouldHoldShrinkingDocumentHeight ? frame.height : newDocumentHeight
        setDocumentSize(CGSize(width: width, height: appliedDocumentHeight))
        guard lastLayoutChangedFrames else {
            return
        }
        applyFrameUpdates(measuredLayout.frameUpdates, animated: shouldAnimate, targetDocumentSize: targetDocumentSize)
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

    func runAfterActiveFrameAnimation(_ completion: @escaping () -> Void) {
        guard hasActiveFrameAnimation else {
            completion()
            return
        }
        activeFrameAnimationCompletions.append(completion)
    }

    func rowFrame(for id: String) -> CGRect? {
        rowFramesByID[id]
    }

    @discardableResult
    func hydrateRows(intersecting hydrationRect: CGRect) -> Int {
        var hydratedCount = 0
        for row in rows {
            guard let rowFrame = rowFramesByID[row.id],
                  rowFrame.intersects(hydrationRect),
                  let hydratableRow = row.view as? AppKitTranscriptViewportHydratable,
                  !hydratableRow.isTranscriptViewportHydrated
            else {
                continue
            }
            hydratableRow.hydrateForTranscriptViewport()
            hydratedCount += 1
        }
        return hydratedCount
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

        // Commit width before measuring because transcript rows wrap against their
        // current AppKit frame; clean rows still get fresh frames for anchor math.
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

    private func measuredRowLayout(
        contentWidth: CGFloat,
        previousFramesByID: [String: CGRect]
    ) -> (frameUpdates: [RowFrameUpdate], documentHeight: CGFloat) {
        var currentY = topInset
        var frameUpdates: [RowFrameUpdate] = []
        isMeasuringRows = true
        defer { isMeasuringRows = false }
        for row in rows {
            let rowHeight = measuredHeight(for: row, contentWidth: contentWidth, currentY: currentY)
            let rowFrame = CGRect(x: transcriptScrollLeadingInset, y: currentY, width: contentWidth, height: rowHeight)
            frameUpdates.append(RowFrameUpdate(view: row.view, frame: rowFrame, previousFrame: previousFramesByID[row.id]))
            rowFramesByID[row.id] = rowFrame
            currentY += rowHeight + rowSpacing
        }
        if !rows.isEmpty {
            currentY -= rowSpacing
        }
        return (frameUpdates, currentY + bottomInset)
    }

    private func rowCacheKey(for row: AppKitTranscriptLayoutRow) -> RowCacheKey { RowCacheKey(id: row.id, viewID: ObjectIdentifier(row.view)) }

    private func hasLayoutChanges(
        frameUpdates: [RowFrameUpdate],
        documentWidth: CGFloat,
        documentHeight: CGFloat
    ) -> Bool {
        let frameChanged = frameUpdates.contains { update in
            guard let previousFrame = update.previousFrame else {
                return true
            }
            return !previousFrame.isApproximatelyEqual(to: update.frame)
        }
        let documentSizeChanged = abs(frame.height - documentHeight) > 0.5 || abs(frame.width - documentWidth) > 0.5
        return frameChanged || documentSizeChanged
    }
}
