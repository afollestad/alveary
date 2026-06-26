@preconcurrency import AppKit
import BlockInputKit
import Foundation
import QuartzCore

@MainActor
final class AppKitTranscriptNestedSubAgentRowsView: NSView {
    struct Configuration: Equatable {
        let agents: [SubAgentEntry]
        let typography: TranscriptTypography
    }

    var onHeightInvalidated: (() -> Void)?
    var onUserInitiatedHeightChange: (() -> Void)? {
        didSet {
            rowViews.forEach { $0.onUserInitiatedHeightChange = onUserInitiatedHeightChange }
        }
    }
    var onOpenMarkdownLink: ((URL) -> Void)? {
        didSet {
            rowViews.forEach { $0.onOpenMarkdownLink = onOpenMarkdownLink }
        }
    }
    var onOpenMarkdownImage: ((BlockInputImage, URL?) -> Void)? {
        didSet {
            rowViews.forEach { $0.onOpenMarkdownImage = onOpenMarkdownImage }
        }
    }
    var onOpenToolImage: ((ToolEntry) -> Void)? {
        didSet {
            rowViews.forEach { $0.onOpenToolImage = onOpenToolImage }
        }
    }

    private let connectorView = AppKitTranscriptSubAgentConnectorView()
    private var rowViews: [AppKitTranscriptSubAgentInlineRowView] = []
    private var rowViewsByAgentID: [String: AppKitTranscriptSubAgentInlineRowView] = [:]
    private var configuration: Configuration?
    private var lastMeasuredHeight: CGFloat = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(connectorView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight())
    }

    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else {
            return
        }
        self.configuration = configuration
        let liveAgentIDs = Set(configuration.agents.map(\.id))
        rowViewsByAgentID = rowViewsByAgentID.filter { agentID, row in
            if liveAgentIDs.contains(agentID) {
                return true
            }
            row.removeFromSuperview()
            return false
        }
        // Keep child views keyed by agent id so nested expansion survives parent
        // refreshes while sub-agent tools or results stream in.
        rowViews = configuration.agents.map { agent in
            let row = rowViewsByAgentID[agent.id] ?? AppKitTranscriptSubAgentInlineRowView()
            rowViewsByAgentID[agent.id] = row
            row.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
            row.onUserInitiatedHeightChange = onUserInitiatedHeightChange
            row.onOpenMarkdownLink = onOpenMarkdownLink
            row.onOpenMarkdownImage = onOpenMarkdownImage
            row.onOpenToolImage = onOpenToolImage
            row.configure(
                .init(
                    agent: agent,
                    canExpand: agent.appKitRendersDetails,
                    showsLeadingIcon: false,
                    typography: configuration.typography
                )
            )
            if row.superview == nil {
                addSubview(row)
            }
            return row
        }
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    override func layout() {
        var currentY = transcriptToolNestedTopSpacing
        let metrics = transcriptInlineToolRowMetrics(for: configuration?.typography ?? TranscriptTypography())
        let rowLeadingInset = metrics.detailLeadingInset
        let rowWidth = max(bounds.width - rowLeadingInset, 0)
        for row in rowViews {
            row.frame = NSRect(
                x: rowLeadingInset,
                y: currentY,
                width: rowWidth,
                height: CGFloat.greatestFiniteMagnitude / 2
            )
            row.layoutSubtreeIfNeeded()
            row.frame.size.height = row.intrinsicContentSize.height
            currentY = row.frame.maxY + transcriptToolNestedRowSpacing
        }
        connectorView.metrics = metrics
        connectorView.frame = bounds
        connectorView.centers = rowViews.map { $0.frame.minY + $0.headerVisualCenterY }
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    private func measuredHeight() -> CGFloat {
        guard !rowViews.isEmpty else {
            return 0
        }
        let rowHeights = rowViews.reduce(CGFloat.zero) { partialResult, row in
            partialResult + ceil(row.intrinsicContentSize.height)
        }
        return transcriptToolNestedTopSpacing + rowHeights + CGFloat(rowViews.count - 1) * transcriptToolNestedRowSpacing
    }

    private func invalidateTranscriptHeight(force: Bool) {
        let newHeight = measuredHeight()
        guard force || abs(newHeight - lastMeasuredHeight) > 0.5 else {
            return
        }
        lastMeasuredHeight = newHeight
        invalidateIntrinsicContentSize()
        onHeightInvalidated?()
    }

    private func childHeightInvalidated() {
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }
}

@MainActor
final class AppKitTranscriptSubAgentInlineRowView: NSView {
    struct Configuration: Equatable {
        let agent: SubAgentEntry
        let canExpand: Bool
        let initiallyExpanded: Bool
        let showsLeadingIcon: Bool
        let typography: TranscriptTypography

        init(
            agent: SubAgentEntry,
            canExpand: Bool,
            initiallyExpanded: Bool = false,
            showsLeadingIcon: Bool = true,
            typography: TranscriptTypography
        ) {
            self.agent = agent
            self.canExpand = canExpand
            self.initiallyExpanded = initiallyExpanded
            self.showsLeadingIcon = showsLeadingIcon
            self.typography = typography
        }
    }

    var onHeightInvalidated: (() -> Void)?
    var onExpansionChanged: ((Bool) -> Void)?
    var onUserInitiatedHeightChange: (() -> Void)? {
        didSet {
            contentView.onUserInitiatedHeightChange = onUserInitiatedHeightChange
        }
    }
    var onOpenMarkdownLink: ((URL) -> Void)? {
        didSet {
            contentView.onOpenMarkdownLink = onOpenMarkdownLink
        }
    }
    var onOpenMarkdownImage: ((BlockInputImage, URL?) -> Void)? {
        didSet {
            contentView.onOpenMarkdownImage = onOpenMarkdownImage
        }
    }
    var onOpenToolImage: ((ToolEntry) -> Void)? {
        didSet {
            contentView.onOpenToolImage = onOpenToolImage
        }
    }

    private let clipView = AppKitTranscriptExpandableClipView()
    private let headerView = AppKitTranscriptToolHeaderRowView()
    private let contentView = AppKitSubAgentExpandedContentView()
    private var configuration: Configuration?
    private var isExpanded = false
    private var lastMeasuredHeight: CGFloat = -1
    private var localClipAnimationToken = UUID()
    private var isBatchingChildHeightInvalidations = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        clipView.translatesAutoresizingMaskIntoConstraints = true
        headerView.translatesAutoresizingMaskIntoConstraints = true
        contentView.translatesAutoresizingMaskIntoConstraints = true
        headerView.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        contentView.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        contentView.onUserInitiatedHeightChange = onUserInitiatedHeightChange
        contentView.onOpenMarkdownLink = onOpenMarkdownLink
        contentView.onOpenMarkdownImage = onOpenMarkdownImage
        contentView.onOpenToolImage = onOpenToolImage
        addSubview(clipView)
        clipView.addSubview(headerView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight())
    }

    var headerVisualCenterY: CGFloat {
        headerView.frame.midY
    }

    func configure(_ configuration: Configuration) {
        let previousConfiguration = self.configuration
        let shouldResetExpansion = self.configuration?.agent.id != configuration.agent.id
        let shouldSyncExpansion = !shouldResetExpansion &&
            previousConfiguration?.initiallyExpanded != configuration.initiallyExpanded &&
            isExpanded != configuration.initiallyExpanded
        self.configuration = configuration
        if shouldResetExpansion {
            isExpanded = configuration.canExpand ? configuration.initiallyExpanded : false
        } else if shouldSyncExpansion {
            isExpanded = configuration.canExpand ? configuration.initiallyExpanded : false
        } else if !configuration.canExpand {
            isExpanded = false
        }
        rebuildAndPrelayoutExpandedContent()
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    func setExpanded(_ expanded: Bool) {
        guard configuration?.canExpand == true,
              isExpanded != expanded else {
            return
        }
        let previousHeight = measuredHeight()
        onUserInitiatedHeightChange?()
        isExpanded = expanded
        rebuildAndPrelayoutExpandedContent()
        prepareLocalClipAnimationIfNeeded(from: previousHeight)
        needsLayout = true
        invalidateTranscriptHeight(force: true)
        onExpansionChanged?(expanded)
    }

    override func layout() {
        layoutContent()
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    private func layoutContent() {
        let width = max(bounds.width, 0)
        headerView.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude / 2)
        headerView.layoutSubtreeIfNeeded()
        headerView.frame.size.height = headerView.intrinsicContentSize.height

        if isExpanded {
            contentView.frame = NSRect(
                x: 0,
                y: headerView.frame.maxY,
                width: width,
                height: CGFloat.greatestFiniteMagnitude / 2
            )
            contentView.layoutSubtreeIfNeeded()
            contentView.frame.size.height = contentView.intrinsicContentSize.height
        }
        clipView.updateFrame(width: width, targetHeight: measuredHeight())
    }

    private func rebuild() {
        guard let configuration else {
            return
        }
        headerView.onToggle = configuration.canExpand ? { [weak self] in
            guard let self else {
                return
            }
            self.setExpanded(!self.isExpanded)
        } : nil
        headerView.configure(
            .init(
                summary: configuration.agent.description,
                leadingIcon: .subAgent,
                phase: ToolStatusPhase(isError: configuration.agent.appKitHasFailedTool, isComplete: configuration.agent.isComplete),
                isExpanded: configuration.canExpand ? isExpanded : nil,
                showsLeadingIcon: configuration.showsLeadingIcon,
                typography: configuration.typography,
                bottomPadding: isExpanded ? 0 : transcriptInlineToolRowVerticalPadding
            )
        )

        if isExpanded {
            if contentView.superview == nil {
                clipView.addSubview(contentView)
            }
            contentView.onOpenMarkdownLink = onOpenMarkdownLink
            contentView.onOpenMarkdownImage = onOpenMarkdownImage
            contentView.onOpenToolImage = onOpenToolImage
            contentView.onUserInitiatedHeightChange = onUserInitiatedHeightChange
            let metrics = transcriptInlineToolRowMetrics(for: configuration.typography)
            contentView.configure(
                .init(
                    agent: configuration.agent,
                    typography: configuration.typography,
                    directContentLeadingInset: metrics.directDetailLeadingInset(showsLeadingIcon: configuration.showsLeadingIcon)
                )
            )
        } else {
            contentView.removeFromSuperview()
        }
    }

    private func measuredHeight() -> CGFloat {
        let headerHeight = headerView.frame.height > 0 ? headerView.frame.height : headerView.intrinsicContentSize.height
        guard isExpanded else {
            return ceil(headerHeight)
        }
        let contentHeight = contentView.intrinsicContentSize.height
        return ceil(headerHeight + contentHeight)
    }

    private func invalidateTranscriptHeight(force: Bool) {
        let newHeight = measuredHeight()
        guard force || abs(newHeight - lastMeasuredHeight) > 0.5 else {
            return
        }
        lastMeasuredHeight = newHeight
        invalidateIntrinsicContentSize()
        onHeightInvalidated?()
    }

    private func childHeightInvalidated() {
        needsLayout = true
        guard !isBatchingChildHeightInvalidations else {
            return
        }
        invalidateTranscriptHeight(force: true)
    }

    private func rebuildAndPrelayoutExpandedContent() {
        isBatchingChildHeightInvalidations = true
        defer { isBatchingChildHeightInvalidations = false }
        rebuild()
        prelayoutExpandedContentIfPossible()
    }

    private func prelayoutExpandedContentIfPossible() {
        guard isExpanded, bounds.width > 0 else {
            return
        }
        layoutContent()
    }

    private func prepareLocalClipAnimationIfNeeded(from previousHeight: CGFloat) {
        guard window != nil,
              bounds.width > 0 else {
            return
        }
        let targetHeight = measuredHeight()
        guard previousHeight > 0,
              targetHeight > 0,
              abs(previousHeight - targetHeight) > 0.5 else {
            return
        }
        clipView.prepareVisibleHeightAnimation(from: previousHeight, to: targetHeight, width: bounds.width)
        localClipAnimationToken = UUID()
        let token = localClipAnimationToken
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.localClipAnimationToken == token,
                  self.clipView.isAnimatingVisibleHeight else {
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = appExpansionAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.clipView.animateVisibleHeightChange()
            } completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.finishLocalClipAnimation(token: token)
                }
            }
            self.scheduleLocalClipAnimationFallback(token: token)
        }
    }

    private func scheduleLocalClipAnimationFallback(token: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + appExpansionAnimationDuration + 0.5) { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishLocalClipAnimation(token: token)
            }
        }
    }

    private func finishLocalClipAnimation(token: UUID) {
        guard localClipAnimationToken == token,
              clipView.isAnimatingVisibleHeight else {
            return
        }
        clipView.finishVisibleHeightAnimation()
    }
}

@MainActor
private final class AppKitTranscriptSubAgentConnectorView: NSView {
    var metrics = transcriptInlineToolRowMetrics(for: TranscriptTypography()) {
        didSet {
            needsDisplay = true
        }
    }

    var centers: [CGFloat] = [] {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let lastCenter = centers.last else {
            return
        }

        transcriptInlineToolRowColor.withAlphaComponent(transcriptToolConnectorOpacity).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        let verticalX = metrics.controlSize / 2
        let horizontalEndX = metrics.detailLeadingInset - transcriptToolElbowGap
        path.move(to: CGPoint(x: verticalX, y: transcriptToolNestedTopSpacing))
        path.line(to: CGPoint(x: verticalX, y: lastCenter))
        for center in centers {
            path.move(to: CGPoint(x: verticalX, y: center))
            path.line(to: CGPoint(x: horizontalEndX, y: center))
        }
        path.stroke()
    }
}
