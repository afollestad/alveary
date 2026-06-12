@preconcurrency import AppKit
import Foundation

@MainActor
final class AppKitTranscriptToolGroupView: NSView {
    struct Configuration: Equatable {
        let tools: [ToolEntry]
        let initiallyExpanded: Bool
        let maxWidth: CGFloat
        let typography: TranscriptTypography

        init(
            tools: [ToolEntry],
            initiallyExpanded: Bool = false,
            maxWidth: CGFloat = .infinity,
            typography: TranscriptTypography = TranscriptTypography()
        ) {
            self.tools = tools
            self.initiallyExpanded = initiallyExpanded
            self.maxWidth = maxWidth
            self.typography = typography
        }
    }

    var onHeightInvalidated: (() -> Void)?
    var onUserInitiatedHeightChange: (() -> Void)? {
        didSet {
            singleToolRow.onUserInitiatedHeightChange = onUserInitiatedHeightChange
            nestedRowsView.onUserInitiatedHeightChange = onUserInitiatedHeightChange
        }
    }
    var onExpansionChanged: ((Bool) -> Void)? {
        didSet {
            singleToolRow.onExpansionChanged = onExpansionChanged
        }
    }
    var onOpenMarkdownLink: ((URL) -> Void)? {
        didSet {
            singleToolRow.onOpenMarkdownLink = onOpenMarkdownLink
            nestedRowsView.onOpenMarkdownLink = onOpenMarkdownLink
        }
    }

    private let clipView = AppKitTranscriptExpandableClipView()
    private let headerView = AppKitTranscriptToolHeaderRowView()
    private let singleToolRow = AppKitTranscriptInlineToolRowView()
    private let nestedRowsView = AppKitTranscriptNestedToolRowsView()
    private var configuration: Configuration?
    private var isExpanded = false
    private var lastMeasuredHeight: CGFloat = -1
    private var isBatchingChildHeightInvalidations = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
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
        let previousConfiguration = self.configuration
        let previousIDs = self.configuration?.tools.map(\.id)
        let shouldResetExpansion = previousIDs != configuration.tools.map(\.id)
        let shouldRebuild = shouldResetExpansion ||
            previousConfiguration?.tools != configuration.tools ||
            previousConfiguration?.maxWidth != configuration.maxWidth ||
            previousConfiguration?.typography != configuration.typography
        self.configuration = configuration
        if shouldResetExpansion {
            isExpanded = configuration.initiallyExpanded
        }
        // Local expansion changes echo back through SwiftUI as persisted
        // `initiallyExpanded`; avoid rebuilding the already-updated group mid-animation.
        guard shouldRebuild else {
            return
        }
        rebuildAndPrelayoutExpandedContent()
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else {
            return
        }
        onUserInitiatedHeightChange?()
        isExpanded = expanded
        rebuildAndPrelayoutExpandedContent()
        needsLayout = true
        invalidateTranscriptHeight(force: true)
        onExpansionChanged?(expanded)
    }

    override func layout() {
        layoutContent()
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        clipView.translatesAutoresizingMaskIntoConstraints = true
        headerView.translatesAutoresizingMaskIntoConstraints = true
        singleToolRow.translatesAutoresizingMaskIntoConstraints = true
        nestedRowsView.translatesAutoresizingMaskIntoConstraints = true
        headerView.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        singleToolRow.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        nestedRowsView.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        singleToolRow.onOpenMarkdownLink = onOpenMarkdownLink
        singleToolRow.onUserInitiatedHeightChange = onUserInitiatedHeightChange
        singleToolRow.onExpansionChanged = onExpansionChanged
        nestedRowsView.onOpenMarkdownLink = onOpenMarkdownLink
        nestedRowsView.onUserInitiatedHeightChange = onUserInitiatedHeightChange
        addSubview(clipView)
    }

    private func rebuild() {
        guard let configuration else {
            return
        }

        clipView.subviews.forEach { $0.removeFromSuperview() }
        guard !configuration.tools.isEmpty else {
            return
        }
        if configuration.tools.count <= 1, let only = configuration.tools.first {
            clipView.addSubview(singleToolRow)
            singleToolRow.onOpenMarkdownLink = onOpenMarkdownLink
            singleToolRow.onUserInitiatedHeightChange = onUserInitiatedHeightChange
            singleToolRow.onExpansionChanged = onExpansionChanged
            singleToolRow.configure(
                .init(
                    tool: only,
                    initiallyExpanded: isExpanded,
                    canExpand: only.appKitRendersDetails,
                    maxWidth: configuration.maxWidth,
                    typography: configuration.typography
                )
            )
            return
        }

        clipView.addSubview(headerView)
        headerView.onToggle = { [weak self] in
            guard let self else {
                return
            }
            self.setExpanded(!self.isExpanded)
        }
        headerView.configure(
            .init(
                summary: summary(for: configuration.tools),
                leadingIcon: ToolEntry.transcriptGroupLeadingIconKind(for: configuration.tools),
                phase: aggregateStatusPhase(for: configuration.tools),
                isExpanded: isExpanded,
                debounceStatus: true,
                typography: configuration.typography,
                bottomPadding: isExpanded ? 0 : transcriptInlineToolRowVerticalPadding
            )
        )

        if isExpanded {
            clipView.addSubview(nestedRowsView)
            nestedRowsView.onOpenMarkdownLink = onOpenMarkdownLink
            nestedRowsView.onUserInitiatedHeightChange = onUserInitiatedHeightChange
            nestedRowsView.configure(.init(tools: configuration.tools, typography: configuration.typography))
        }
    }

    private func layoutContent() {
        guard let configuration else {
            return
        }
        let width = contentWidth(for: configuration)
        guard !configuration.tools.isEmpty else {
            clipView.updateFrame(width: width, targetHeight: 0)
            return
        }
        if configuration.tools.count <= 1 {
            singleToolRow.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude / 2)
            singleToolRow.layoutSubtreeIfNeeded()
            singleToolRow.frame.size.height = singleToolRow.intrinsicContentSize.height
            clipView.updateFrame(width: width, targetHeight: singleToolRow.frame.height)
            return
        }

        headerView.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude / 2)
        headerView.layoutSubtreeIfNeeded()
        headerView.frame.size.height = headerView.intrinsicContentSize.height

        guard isExpanded else {
            clipView.updateFrame(width: width, targetHeight: headerView.frame.height)
            return
        }
        nestedRowsView.frame = NSRect(
            x: 0,
            y: headerView.frame.maxY,
            width: width,
            height: CGFloat.greatestFiniteMagnitude / 2
        )
        nestedRowsView.layoutSubtreeIfNeeded()
        nestedRowsView.frame.size.height = nestedRowsView.intrinsicContentSize.height
        clipView.updateFrame(width: width, targetHeight: measuredHeight())
    }

    private func contentWidth(for configuration: Configuration?) -> CGFloat {
        let availableWidth = max(bounds.width, 0)
        guard let configuration else {
            return availableWidth
        }
        let maxWidth = configuration.maxWidth.isFinite ? configuration.maxWidth : availableWidth
        return min(max(maxWidth, 0), availableWidth)
    }

    private func measuredHeight() -> CGFloat {
        guard let configuration else {
            return 0
        }
        guard !configuration.tools.isEmpty else {
            return 0
        }
        if configuration.tools.count <= 1 {
            return ceil(singleToolRow.intrinsicContentSize.height)
        }
        let headerHeight = headerView.frame.height > 0 ? headerView.frame.height : headerView.intrinsicContentSize.height
        guard isExpanded else {
            return ceil(headerHeight)
        }
        let nestedHeight = nestedRowsView.intrinsicContentSize.height
        return ceil(headerHeight + nestedHeight)
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

    private func summary(for tools: [ToolEntry]) -> String {
        let summaries = categorySummaries(for: tools)
        guard let first = summaries.first else {
            return ""
        }
        let tail = summaries.dropFirst().map(TranscriptToolGroupSummaryFormatter.lowercasedFirstLetter)
        return ([first] + tail).joined(separator: ", ")
    }

    private func aggregateStatusPhase(for tools: [ToolEntry]) -> ToolStatusPhase {
        ToolStatusPhase(
            isError: tools.contains(where: \.isError),
            isComplete: !tools.isEmpty && tools.allSatisfy(\.isComplete)
        )
    }

    private func categorySummaries(for tools: [ToolEntry]) -> [String] {
        let isComplete = !tools.isEmpty && tools.allSatisfy(\.isComplete)
        var order: [String] = []
        var counts: [String: Int] = [:]
        for tool in tools {
            let key = TranscriptToolGroupSummaryFormatter.toolCategoryKey(for: tool.name)
            if counts[key] == nil {
                order.append(key)
            }
            counts[key, default: 0] += 1
        }
        return order.map { key in
            TranscriptToolGroupSummaryFormatter.toolCategorySummary(for: key, count: counts[key] ?? 0, isComplete: isComplete)
        }
    }
}

extension AppKitTranscriptToolGroupView: AppKitTranscriptFrameAnimatable {
    func prepareSynchronizedFrameAnimation(from previousFrame: NSRect, to targetFrame: NSRect) {
        let targetWidth = min(contentWidth(for: configuration), targetFrame.width)
        clipView.prepareVisibleHeightAnimation(from: previousFrame.height, to: targetFrame.height, width: targetWidth)
    }

    func animateSynchronizedFrameChange() {
        clipView.animateVisibleHeightChange()
    }

    func finishSynchronizedFrameAnimation() {
        clipView.finishVisibleHeightAnimation()
    }
}
