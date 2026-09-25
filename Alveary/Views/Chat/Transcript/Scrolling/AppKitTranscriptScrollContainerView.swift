import AppKit
import QuartzCore

@MainActor
final class AppKitTranscriptScrollContainerView: NSView {
    let scrollView = NSScrollView()
    let transcriptDocumentView = AppKitTranscriptDocumentLayoutView()
    var activeScrollAnimationToken: UUID?
    private(set) var paginationGeneration = 0
    /// A new receiver gets the current metrics even when they match the last publish.
    var onScrollMetricsChanged: ((ChatTranscriptScrollMetrics) -> Void)? {
        didSet { lastPublishedScrollMetrics = nil }
    }
    /// Called only after real-width layout settles, including an empty document awaiting prepared rows.
    var onStableLayout: (() -> Void)?
    var preservesBottomOnResize = true
    var shouldForceBottomAfterCurrentMeasurement = false
    var layoutTransactionDepth = 0
    private var isRunningNativeLayout = false
    var pendingConfiguration: AppKitTranscriptPendingConfiguration?
    var hasQueuedAnimationLayout = false
    var pendingHeightInvalidation: AppKitTranscriptHeightInvalidation?
    var hasScheduledHeightInvalidationFlush = false
    let loadingIndicator = NSProgressIndicator()
    private(set) var isLoadingForTesting = false
    var viewportPrewarmTask: Task<Void, Never>?
    var viewportPrewarmCandidates: [AppKitTranscriptPrewarmCandidate] = []
    var viewportPrewarmRegistry: [String: AppKitTranscriptPrewarmRegistryEntry] = [:]
    var viewportPrewarmRowOrder: [String] = []
    var viewportPrewarmGeneration = 0
    private(set) var hasMountedWindow = false
    private var rowIDAliases: [String: String] = [:]
    private var lastPublishedScrollMetrics: ChatTranscriptScrollMetrics?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUpScrollView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpScrollView()
    }

    deinit {
        viewportPrewarmTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        isRunningNativeLayout = true
        defer { isRunningNativeLayout = false }
        super.layout()
        layoutTranscriptContainer()
    }

    /// Native layout callbacks can install or invalidate rows while AppKit defers recursive layout requests.
    private func layoutAtCurrentWidth() {
        needsLayout = true
        if isRunningNativeLayout {
            layoutTranscriptContainer()
        } else {
            layoutSubtreeIfNeeded()
        }
    }

    func configure(
        rows: [AppKitTranscriptLayoutRow],
        dirtyRowIDs: Set<String> = [],
        rowIDAliases: [String: String] = [:],
        preserveBottomIfFollowing: Bool
    ) {
        preservesBottomOnResize = preserveBottomIfFollowing
        if transcriptDocumentView.hasActiveFrameAnimation {
            pendingConfiguration = AppKitTranscriptPendingConfiguration(
                rows: rows,
                dirtyRowIDs: dirtyRowIDs.union(pendingConfiguration?.dirtyRowIDs ?? []),
                rowIDAliases: rowIDAliases
            )
            queueLayoutAfterFrameAnimation()
            return
        }
        beginLayoutTransaction()
        defer { endLayoutTransaction() }
        let shouldRestoreBottom = preserveBottomIfFollowing && isAtBottom
        let visibleAnchor = captureVisibleAnchor()
        self.rowIDAliases = rowIDAliases
        let canonicalDirtyRowIDs = Set(dirtyRowIDs.map(canonicalRowID(for:)))
        transcriptDocumentView.configure(rows: rows, dirtyRowIDs: canonicalDirtyRowIDs)
        refreshViewportPrewarmRegistry(rows: rows, dirtyRowIDs: canonicalDirtyRowIDs)
        layoutAtCurrentWidth()
        // Measurement feedback belongs to this transaction; retaining it would replay an old follow request after a later user scroll.
        if restoreForcedBottomAfterMeasurementIfNeeded() {
            return
        }
        restoreScrollPosition(shouldRestoreBottom: shouldRestoreBottom, visibleAnchor: visibleAnchor)
    }

    func rowHeightInvalidated(
        rowID: String? = nil,
        preserveBottomIfFollowing: Bool,
        forceBottomIfPreserving: Bool = false,
        animatesLayoutChanges: Bool = true
    ) {
        rowHeightsInvalidated(
            rowIDs: rowID.map { [$0] },
            preserveBottomIfFollowing: preserveBottomIfFollowing,
            forceBottomIfPreserving: forceBottomIfPreserving,
            animatesLayoutChanges: animatesLayoutChanges
        )
    }

    /// Measures every dirty row before starting one animation; nil retains the unknown-row fallback.
    func rowHeightsInvalidated(
        rowIDs: Set<String>?,
        preserveBottomIfFollowing: Bool,
        forceBottomIfPreserving: Bool,
        animatesLayoutChanges: Bool
    ) {
        // Named invalidation is the hot path; nil stays available when callers
        // cannot identify the changed row. Reentrant measurement feedback is
        // satisfied by the active pass to avoid staggered row animations.
        if deferHeightInvalidationUntilStable(
            rowIDs: rowIDs,
            preserveBottomIfFollowing: preserveBottomIfFollowing,
            forceBottomIfPreserving: forceBottomIfPreserving,
            animatesLayoutChanges: animatesLayoutChanges
        ) {
            return
        }
        let shouldRestoreBottom = preserveBottomIfFollowing && (isAtBottom || forceBottomIfPreserving)
        let visibleAnchor = captureVisibleAnchor()
        let documentHeightBeforeLayout = documentHeight
        let revisionBeforeLayout = transcriptDocumentView.layoutRevision
        beginLayoutTransaction()
        defer { endLayoutTransaction() }
        let canonicalRowIDs = rowIDs.map { Set($0.map(canonicalRowID(for:))) }
        refreshViewportPrewarmRegistry(rowIDs: canonicalRowIDs)
        if let canonicalRowIDs {
            canonicalRowIDs.forEach { transcriptDocumentView.markRowHeightDirty($0) }
        } else {
            transcriptDocumentView.markAllRowHeightsDirty()
        }
        if animatesLayoutChanges {
            transcriptDocumentView.animateNextLayoutChange()
        }
        layoutAtCurrentWidth()
        if restoreForcedBottomAfterMeasurementIfNeeded() {
            return
        }
        // A named dirty row can remeasure to the same frame; in that hot path
        // downstream frames and visible anchors are already stable.
        guard rowIDs == nil || transcriptDocumentView.layoutRevision != revisionBeforeLayout else {
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

    var isAtBottom: Bool {
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
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isDisplayedWhenStopped = false
        loadingIndicator.setAccessibilityLabel("Loading conversation")
        loadingIndicator.isHidden = true
        addSubview(loadingIndicator)
        transcriptDocumentView.onLayoutDeferredByAnimation = { [weak self] in
            self?.queueLayoutAfterFrameAnimation()
        }
        transcriptDocumentView.onFrameAnimationCompleted = { [weak self] in
            self?.notifyStableLayoutIfNeeded()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    private func scroll(toY proposedY: CGFloat) {
        scrollContentView(toY: proposedY)
        guard layoutTransactionDepth == 0 else { return }
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
        guard layoutTransactionDepth == 0 else { return }
        if scrollView.contentView.bounds.minX != 0 {
            scrollView.contentView.scroll(to: CGPoint(x: 0, y: scrollOffsetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        hydrateViewportRows()
        publishScrollMetrics()
    }

    @discardableResult
    func hydrateViewportRows() -> Int {
        let signpost = AppKitTranscriptSignposts.begin("hydrateViewportRows")
        defer { AppKitTranscriptSignposts.end(signpost) }
        let visibleRect = scrollView.contentView.bounds
        let prefetchMargin = visibleRect.height * 1.5
        let hydrationRect = visibleRect.insetBy(dx: 0, dy: -prefetchMargin)
        let documentHeightBeforeHydration = documentHeight
        let hydratedCount = transcriptDocumentView.hydrateRows(intersecting: hydrationRect)
        assert(abs(documentHeight - documentHeightBeforeHydration) <= 0.5, "Viewport hydration changed transcript document height")
        updateViewportPrewarming(in: hydrationRect)
        return hydratedCount
    }

    /// Publishes only when the metrics moved. Every streaming tick and viewport hydration ends
    /// here, and each publish re-evaluates the SwiftUI transcript body, so a repeat of the last
    /// metrics would cost a full bridge update for nothing.
    func publishScrollMetrics() {
        guard layoutTransactionDepth == 0, !isLoadingForTesting else { return }
        let metrics = ChatTranscriptScrollMetrics(
            offsetY: scrollOffsetY,
            contentHeight: documentHeight,
            containerHeight: scrollView.contentView.bounds.height
        )
        guard metrics != lastPublishedScrollMetrics else { return }
        lastPublishedScrollMetrics = metrics
        onScrollMetricsChanged?(metrics)
    }

    func setIsLoading(_ isLoading: Bool) {
        guard isLoadingForTesting != isLoading else { return }
        isLoadingForTesting = isLoading
        loadingIndicator.isHidden = !isLoading
        if isLoading {
            loadingIndicator.startAnimation(nil)
        } else {
            loadingIndicator.stopAnimation(nil)
            publishScrollMetrics()
        }
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            cancelViewportPrewarming()
        } else {
            hasMountedWindow = true
            hydrateViewportRows()
        }
    }
}
