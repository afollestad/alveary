@preconcurrency import AppKit
import BlockInputKit
import Foundation

@MainActor
final class AppKitTranscriptSubAgentBlockView: NSView {
    struct Configuration: Equatable {
        let agents: [SubAgentEntry]
        let initiallyExpanded: Bool
        let canExpand: Bool
        let maxWidth: CGFloat
        let typography: TranscriptTypography

        init(
            agents: [SubAgentEntry],
            initiallyExpanded: Bool = false,
            canExpand: Bool? = nil,
            maxWidth: CGFloat = .infinity,
            typography: TranscriptTypography = TranscriptTypography()
        ) {
            self.agents = agents
            self.initiallyExpanded = initiallyExpanded
            self.canExpand = canExpand ?? Self.defaultCanExpand(agents)
            self.maxWidth = maxWidth
            self.typography = typography
        }

        private static func defaultCanExpand(_ agents: [SubAgentEntry]) -> Bool {
            agents.appKitSubAgentBlockRendersDetails
        }
    }

    var onHeightInvalidated: (() -> Void)?
    var onUserInitiatedHeightChange: (() -> Void)? {
        didSet {
            singleAgentContentView.onUserInitiatedHeightChange = onUserInitiatedHeightChange
            nestedAgentsView.onUserInitiatedHeightChange = onUserInitiatedHeightChange
        }
    }
    var onExpansionChanged: ((Bool) -> Void)?
    var onOpenMarkdownLink: ((URL) -> Void)? {
        didSet {
            singleAgentContentView.onOpenMarkdownLink = onOpenMarkdownLink
            nestedAgentsView.onOpenMarkdownLink = onOpenMarkdownLink
        }
    }
    var onOpenMarkdownImage: ((BlockInputImage, URL?) -> Void)? {
        didSet {
            singleAgentContentView.onOpenMarkdownImage = onOpenMarkdownImage
            nestedAgentsView.onOpenMarkdownImage = onOpenMarkdownImage
        }
    }
    var onOpenToolImage: ((ToolEntry) -> Void)? {
        didSet {
            singleAgentContentView.onOpenToolImage = onOpenToolImage
            nestedAgentsView.onOpenToolImage = onOpenToolImage
        }
    }

    private let clipView = AppKitTranscriptExpandableClipView()
    private let headerView = AppKitTranscriptToolHeaderRowView()
    private let singleAgentContentView = AppKitSubAgentExpandedContentView()
    private let nestedAgentsView = AppKitTranscriptNestedSubAgentRowsView()
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
        let previousAgentIDs = self.configuration?.agents.map(\.id)
        let shouldResetExpansion = previousAgentIDs != configuration.agents.map(\.id)
        let shouldRebuild = shouldResetExpansion ||
            previousConfiguration?.agents != configuration.agents ||
            previousConfiguration?.canExpand != configuration.canExpand ||
            previousConfiguration?.maxWidth != configuration.maxWidth ||
            previousConfiguration?.typography != configuration.typography
        self.configuration = configuration
        if shouldResetExpansion {
            isExpanded = configuration.canExpand ? configuration.initiallyExpanded : false
        } else if !configuration.canExpand {
            isExpanded = false
        }
        guard shouldRebuild else {
            return
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
        singleAgentContentView.translatesAutoresizingMaskIntoConstraints = true
        nestedAgentsView.translatesAutoresizingMaskIntoConstraints = true
        headerView.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        singleAgentContentView.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        nestedAgentsView.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        singleAgentContentView.onUserInitiatedHeightChange = onUserInitiatedHeightChange
        nestedAgentsView.onUserInitiatedHeightChange = onUserInitiatedHeightChange
        singleAgentContentView.onOpenMarkdownLink = onOpenMarkdownLink
        singleAgentContentView.onOpenMarkdownImage = onOpenMarkdownImage
        singleAgentContentView.onOpenToolImage = onOpenToolImage
        nestedAgentsView.onOpenMarkdownLink = onOpenMarkdownLink
        nestedAgentsView.onOpenMarkdownImage = onOpenMarkdownImage
        nestedAgentsView.onOpenToolImage = onOpenToolImage
        addSubview(clipView)
        clipView.addSubview(headerView)
    }

    private func rebuild() {
        guard let configuration else {
            return
        }

        singleAgentContentView.removeFromSuperview()
        nestedAgentsView.removeFromSuperview()
        headerView.onToggle = configuration.canExpand ? { [weak self] in
            guard let self else {
                return
            }
            self.setExpanded(!self.isExpanded)
        } : nil
        headerView.configure(
            .init(
                summary: headerSummary(for: configuration.agents),
                leadingIcon: .subAgent,
                phase: aggregateStatusPhase(for: configuration.agents),
                isExpanded: configuration.canExpand ? isExpanded : nil,
                typography: configuration.typography,
                bottomPadding: isExpanded ? 0 : transcriptInlineToolRowVerticalPadding
            )
        )

        guard isExpanded else {
            return
        }

        if configuration.agents.count == 1, let agent = configuration.agents.first {
            clipView.addSubview(singleAgentContentView)
            singleAgentContentView.onOpenMarkdownLink = onOpenMarkdownLink
            singleAgentContentView.onOpenMarkdownImage = onOpenMarkdownImage
            singleAgentContentView.onOpenToolImage = onOpenToolImage
            singleAgentContentView.onUserInitiatedHeightChange = onUserInitiatedHeightChange
            let metrics = transcriptInlineToolRowMetrics(for: configuration.typography)
            singleAgentContentView.configure(
                .init(
                    agent: agent,
                    typography: configuration.typography,
                    directContentLeadingInset: metrics.detailLeadingInset
                )
            )
        } else {
            clipView.addSubview(nestedAgentsView)
            nestedAgentsView.onOpenMarkdownLink = onOpenMarkdownLink
            nestedAgentsView.onOpenMarkdownImage = onOpenMarkdownImage
            nestedAgentsView.onOpenToolImage = onOpenToolImage
            nestedAgentsView.onUserInitiatedHeightChange = onUserInitiatedHeightChange
            nestedAgentsView.configure(.init(agents: configuration.agents, typography: configuration.typography))
        }
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

        let expandedView: NSView = configuration.agents.count == 1 ? singleAgentContentView : nestedAgentsView
        expandedView.frame = NSRect(
            x: 0,
            y: headerView.frame.maxY,
            width: width,
            height: CGFloat.greatestFiniteMagnitude / 2
        )
        expandedView.layoutSubtreeIfNeeded()
        expandedView.frame.size.height = expandedView.intrinsicContentSize.height
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
        guard let configuration, isExpanded else {
            return ceil(headerHeight)
        }
        let expandedView: NSView = configuration.agents.count == 1 ? singleAgentContentView : nestedAgentsView
        let expandedHeight = expandedView.intrinsicContentSize.height
        return ceil(headerHeight + expandedHeight)
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

    private func headerSummary(for agents: [SubAgentEntry]) -> String {
        if agents.count == 1, let agent = agents.first {
            return "\(agent.isComplete ? "Explored" : "Exploring"): \(agent.description)"
        }
        if agents.allSatisfy(\.isComplete) {
            return agents.count == 1 ? "Explored 1 sub-agent" : "Explored \(agents.count) sub-agents"
        }
        return agents.count == 1 ? "Exploring 1 sub-agent" : "Exploring \(agents.count) sub-agents"
    }

    private func aggregateStatusPhase(for agents: [SubAgentEntry]) -> ToolStatusPhase {
        ToolStatusPhase(
            isError: agents.contains(where: \.appKitHasFailedTool),
            isComplete: !agents.isEmpty && agents.allSatisfy(\.isComplete)
        )
    }
}

extension AppKitTranscriptSubAgentBlockView: AppKitTranscriptFrameAnimatable {
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

extension SubAgentEntry {
    var appKitHasFailedTool: Bool {
        completionDisposition == .failed || tools.contains(where: \.isError)
    }
}
