import AppKit

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
    var onLayoutDeferredByAnimation: (() -> Void)?
    var onFrameAnimationCompleted: (() -> Void)?
    private(set) var isMeasuringRows = false
    var isApplyingFrameUpdates = false
    var hasActiveFrameAnimation = false
    /// Tracks changes across native layout passes so a final cached pass cannot hide an earlier frame change.
    private(set) var layoutRevision = 0

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
        let contentWidth = max(0, width - transcriptScrollLeadingInset - transcriptScrollTrailingInset)
        // Reentrant layout during a measured frame animation must not commit the final document
        // height early, or bottom-pinned collapse visibly jumps. A zero width means no frame yet, and
        // the first real pass re-dirties every row, so measuring here is waste that every mount pays.
        guard !isMeasuringRows, !isApplyingFrameUpdates, contentWidth > 0 else {
            return
        }
        guard !hasActiveFrameAnimation else {
            if activeFrameAnimationTargetDocumentSize?.width != width {
                onLayoutDeferredByAnimation?()
            }
            return
        }
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
        let layoutChangedFrames = hasLayoutChanges(
            frameUpdates: measuredLayout.frameUpdates,
            documentWidth: width,
            documentHeight: newDocumentHeight
        )
        let targetDocumentSize = CGSize(width: width, height: newDocumentHeight)
        let shouldHoldShrinkingDocumentHeight = shouldAnimate && newDocumentHeight < frame.height - 0.5
        let appliedDocumentHeight = shouldHoldShrinkingDocumentHeight ? frame.height : newDocumentHeight
        setDocumentSize(CGSize(width: width, height: appliedDocumentHeight))
        guard layoutChangedFrames else {
            return
        }
        layoutRevision += 1
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
