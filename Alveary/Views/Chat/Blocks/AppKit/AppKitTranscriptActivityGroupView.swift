@preconcurrency import AppKit
import Foundation

@MainActor
final class AppKitTranscriptActivityGroupView: NSView {
    struct Configuration: Equatable {
        let children: [AppKitTranscriptActivityChild]
        let initiallyExpanded: Bool
        let expandedChildIDs: Set<String>
        let maxWidth: CGFloat
        let typography: TranscriptTypography

        init(
            children: [AppKitTranscriptActivityChild],
            initiallyExpanded: Bool = false,
            expandedChildIDs: Set<String> = [],
            maxWidth: CGFloat = .infinity,
            typography: TranscriptTypography = TranscriptTypography()
        ) {
            self.children = children
            self.initiallyExpanded = initiallyExpanded
            self.expandedChildIDs = expandedChildIDs
            self.maxWidth = maxWidth
            self.typography = typography
        }
    }

    var onHeightInvalidated: (() -> Void)?
    var onUserInitiatedHeightChange: (() -> Void)? {
        didSet {
            nestedRowsView.onUserInitiatedHeightChange = onUserInitiatedHeightChange
        }
    }
    var onOpenMarkdownLink: ((URL) -> Void)? {
        didSet {
            nestedRowsView.onOpenMarkdownLink = onOpenMarkdownLink
        }
    }
    var onExpansionChanged: ((Bool) -> Void)?
    var onChildExpansionChanged: ((String, Bool) -> Void)? {
        didSet {
            nestedRowsView.onChildExpansionChanged = onChildExpansionChanged
        }
    }

    private let clipView = AppKitTranscriptExpandableClipView()
    private let headerView = AppKitTranscriptToolHeaderRowView()
    private let nestedRowsView = AppKitTranscriptMixedActivityRowsView()
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
        let previousChildIDs = self.configuration?.children.map(\.id)
        let shouldResetExpansion = previousChildIDs != configuration.children.map(\.id)
        let shouldSyncExpansion = !shouldResetExpansion &&
            previousConfiguration?.initiallyExpanded != configuration.initiallyExpanded &&
            isExpanded != configuration.initiallyExpanded
        let shouldRebuild = shouldResetExpansion ||
            shouldSyncExpansion ||
            previousConfiguration?.children != configuration.children ||
            previousConfiguration?.expandedChildIDs != configuration.expandedChildIDs ||
            previousConfiguration?.maxWidth != configuration.maxWidth ||
            previousConfiguration?.typography != configuration.typography
        self.configuration = configuration
        if shouldResetExpansion {
            isExpanded = configuration.initiallyExpanded
        } else if shouldSyncExpansion {
            isExpanded = configuration.initiallyExpanded
        }
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
        nestedRowsView.translatesAutoresizingMaskIntoConstraints = true
        headerView.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        nestedRowsView.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        nestedRowsView.onOpenMarkdownLink = onOpenMarkdownLink
        nestedRowsView.onUserInitiatedHeightChange = onUserInitiatedHeightChange
        nestedRowsView.onChildExpansionChanged = onChildExpansionChanged
        addSubview(clipView)
    }

    private func rebuild() {
        guard let configuration else {
            return
        }

        clipView.subviews.forEach { $0.removeFromSuperview() }
        headerView.onToggle = { [weak self] in
            guard let self else {
                return
            }
            self.setExpanded(!self.isExpanded)
        }
        headerView.configure(
            .init(
                summary: Self.summary(for: configuration.children),
                leadingIcon: Self.leadingIcon(for: configuration.children),
                phase: Self.aggregateStatusPhase(for: configuration.children),
                isExpanded: isExpanded,
                debounceStatus: true,
                typography: configuration.typography,
                bottomPadding: isExpanded ? 0 : transcriptInlineToolRowVerticalPadding
            )
        )
        clipView.addSubview(headerView)

        guard isExpanded else {
            return
        }

        clipView.addSubview(nestedRowsView)
        nestedRowsView.onOpenMarkdownLink = onOpenMarkdownLink
        nestedRowsView.onUserInitiatedHeightChange = onUserInitiatedHeightChange
        nestedRowsView.onChildExpansionChanged = onChildExpansionChanged
        nestedRowsView.configure(
            .init(
                children: configuration.children,
                expandedChildIDs: configuration.expandedChildIDs,
                typography: configuration.typography
            )
        )
    }

    private func layoutContent() {
        guard let configuration else {
            return
        }
        let width = contentWidth(for: configuration)
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
        let headerHeight = headerView.frame.height > 0 ? headerView.frame.height : headerView.intrinsicContentSize.height
        guard isExpanded else {
            return ceil(headerHeight)
        }
        return ceil(headerHeight + nestedRowsView.intrinsicContentSize.height)
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

    private static func summary(for children: [AppKitTranscriptActivityChild]) -> String {
        let isComplete = !children.isEmpty && children.allSatisfy(\.isComplete)
        var order: [String] = []
        var counts: [String: Int] = [:]
        var subAgentCount = 0

        for child in children {
            switch child {
            case .tool(_, _, let tool):
                let key = TranscriptToolGroupSummaryFormatter.toolCategoryKey(for: tool.name)
                if counts[key] == nil {
                    order.append(key)
                }
                counts[key, default: 0] += 1
            case .subAgent:
                if subAgentCount == 0 {
                    order.append("SubAgent")
                }
                subAgentCount += 1
            }
        }

        let summaries = order.map { key in
            if key == "SubAgent" {
                return TranscriptToolGroupSummaryFormatter.subAgentSummary(count: subAgentCount, isComplete: isComplete)
            }
            return TranscriptToolGroupSummaryFormatter.toolCategorySummary(for: key, count: counts[key] ?? 0, isComplete: isComplete)
        }
        return TranscriptToolGroupSummaryFormatter.joinedSummaries(summaries)
    }

    private static func leadingIcon(for children: [AppKitTranscriptActivityChild]) -> TranscriptToolLeadingIconKind {
        let icons = children.map { child in
            switch child {
            case .tool(_, _, let tool):
                tool.transcriptLeadingIconKind
            case .subAgent:
                TranscriptToolLeadingIconKind.subAgent
            }
        }
        for preferred in [
            TranscriptToolLeadingIconKind.terminal,
            .search,
            .folder,
            .read,
            .document,
            .edit,
            .write,
            .skill,
            .subAgent,
            .genericTool
        ] where icons.contains(preferred) {
            return preferred
        }
        return .toolGroup
    }

    private static func aggregateStatusPhase(for children: [AppKitTranscriptActivityChild]) -> ToolStatusPhase {
        ToolStatusPhase(
            isError: children.contains(where: \.isError),
            isComplete: !children.isEmpty && children.allSatisfy(\.isComplete)
        )
    }
}

extension AppKitTranscriptActivityGroupView: AppKitTranscriptFrameAnimatable {
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
