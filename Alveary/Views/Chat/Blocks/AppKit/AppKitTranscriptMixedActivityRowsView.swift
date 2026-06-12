@preconcurrency import AppKit
import Foundation

@MainActor
final class AppKitTranscriptMixedActivityRowsView: NSView {
    struct Configuration: Equatable {
        let children: [AppKitTranscriptActivityChild]
        let expandedChildIDs: Set<String>
        let typography: TranscriptTypography
    }

    var onHeightInvalidated: (() -> Void)?
    var onUserInitiatedHeightChange: (() -> Void)? {
        didSet {
            toolRowsByID.values.forEach { $0.onUserInitiatedHeightChange = onUserInitiatedHeightChange }
            subAgentRowsByID.values.forEach { $0.onUserInitiatedHeightChange = onUserInitiatedHeightChange }
        }
    }
    var onOpenMarkdownLink: ((URL) -> Void)? {
        didSet {
            toolRowsByID.values.forEach { $0.onOpenMarkdownLink = onOpenMarkdownLink }
            subAgentRowsByID.values.forEach { $0.onOpenMarkdownLink = onOpenMarkdownLink }
        }
    }
    var onChildExpansionChanged: ((String, Bool) -> Void)?

    private let connectorView = AppKitTranscriptElbowConnectorView()
    private var childViews: [NSView] = []
    private var toolRowsByID: [String: AppKitTranscriptInlineToolRowView] = [:]
    private var subAgentRowsByID: [String: AppKitTranscriptSubAgentInlineRowView] = [:]
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
        pruneRows(keeping: Set(configuration.children.map(\.id)))
        childViews = configuration.children.map { childView(for: $0, configuration: configuration) }
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    override func layout() {
        var currentY = transcriptToolNestedTopSpacing
        let metrics = transcriptInlineToolRowMetrics(for: configuration?.typography ?? TranscriptTypography())
        let rowLeadingInset = metrics.detailLeadingInset
        let rowWidth = max(bounds.width - rowLeadingInset, 0)
        for row in childViews {
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
        connectorView.centers = childViews.compactMap(headerCenterY(for:))
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    private func pruneRows(keeping liveIDs: Set<String>) {
        toolRowsByID = toolRowsByID.filter { childID, row in
            if liveIDs.contains(childID) {
                return true
            }
            row.removeFromSuperview()
            return false
        }
        subAgentRowsByID = subAgentRowsByID.filter { childID, row in
            if liveIDs.contains(childID) {
                return true
            }
            row.removeFromSuperview()
            return false
        }
    }

    private func childView(
        for child: AppKitTranscriptActivityChild,
        configuration: Configuration
    ) -> NSView {
        switch child {
        case .tool(_, let expansionID, let tool):
            return toolRow(id: child.id, expansionID: expansionID, tool: tool, configuration: configuration)
        case .subAgent(_, let expansionID, let agent):
            return subAgentRow(id: child.id, expansionID: expansionID, agent: agent, configuration: configuration)
        }
    }

    private func toolRow(
        id: String,
        expansionID: String?,
        tool: ToolEntry,
        configuration: Configuration
    ) -> AppKitTranscriptInlineToolRowView {
        let row = toolRowsByID[id] ?? AppKitTranscriptInlineToolRowView()
        toolRowsByID[id] = row
        row.usesLocalClipAnimationForExpansion = true
        row.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        row.onUserInitiatedHeightChange = onUserInitiatedHeightChange
        row.onOpenMarkdownLink = onOpenMarkdownLink
        row.onExpansionChanged = expansionHandler(for: expansionID)
        row.configure(
            .init(
                tool: tool,
                initiallyExpanded: expansionID.map { configuration.expandedChildIDs.contains($0) } ?? false,
                showsLeadingIcon: false,
                typography: configuration.typography
            )
        )
        if row.superview == nil {
            addSubview(row)
        }
        return row
    }

    private func subAgentRow(
        id: String,
        expansionID: String?,
        agent: SubAgentEntry,
        configuration: Configuration
    ) -> AppKitTranscriptSubAgentInlineRowView {
        let row = subAgentRowsByID[id] ?? AppKitTranscriptSubAgentInlineRowView()
        subAgentRowsByID[id] = row
        row.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        row.onUserInitiatedHeightChange = onUserInitiatedHeightChange
        row.onOpenMarkdownLink = onOpenMarkdownLink
        row.onExpansionChanged = expansionHandler(for: expansionID)
        row.configure(
            .init(
                agent: agent,
                canExpand: agent.appKitRendersDetails,
                initiallyExpanded: expansionID.map { configuration.expandedChildIDs.contains($0) } ?? false,
                showsLeadingIcon: false,
                typography: configuration.typography
            )
        )
        if row.superview == nil {
            addSubview(row)
        }
        return row
    }

    private func expansionHandler(for expansionID: String?) -> ((Bool) -> Void)? {
        expansionID.map { expansionID in
            { [weak self] expanded in self?.onChildExpansionChanged?(expansionID, expanded) }
        }
    }

    private func headerCenterY(for row: NSView) -> CGFloat? {
        if let toolRow = row as? AppKitTranscriptInlineToolRowView {
            return row.frame.minY + toolRow.headerVisualCenterY
        }
        if let subAgentRow = row as? AppKitTranscriptSubAgentInlineRowView {
            return row.frame.minY + subAgentRow.headerVisualCenterY
        }
        return nil
    }

    private func measuredHeight() -> CGFloat {
        guard !childViews.isEmpty else {
            return 0
        }
        let rowHeights = childViews.reduce(CGFloat.zero) { partialResult, row in
            partialResult + ceil(row.intrinsicContentSize.height)
        }
        return transcriptToolNestedTopSpacing + rowHeights + CGFloat(childViews.count - 1) * transcriptToolNestedRowSpacing
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
