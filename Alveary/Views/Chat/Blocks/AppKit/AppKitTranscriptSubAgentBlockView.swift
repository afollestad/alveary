@preconcurrency import AppKit
import Foundation

@MainActor
final class AppKitTranscriptSubAgentBlockView: NSView {
    struct Configuration: Equatable {
        let agents: [SubAgentEntry]
        let initiallyExpanded: Bool
        let typography: TranscriptTypography

        init(
            agents: [SubAgentEntry],
            initiallyExpanded: Bool = false,
            typography: TranscriptTypography = TranscriptTypography()
        ) {
            self.agents = agents
            self.initiallyExpanded = initiallyExpanded
            self.typography = typography
        }
    }

    var onHeightInvalidated: (() -> Void)?
    var onExpansionChanged: ((Bool) -> Void)?
    var onOpenMarkdownLink: ((URL) -> Void)? {
        didSet {
            singleAgentContentView.onOpenMarkdownLink = onOpenMarkdownLink
            nestedAgentsView.onOpenMarkdownLink = onOpenMarkdownLink
        }
    }

    private let headerView = AppKitTranscriptToolHeaderRowView()
    private let singleAgentContentView = AppKitSubAgentExpandedContentView()
    private let nestedAgentsView = AppKitTranscriptNestedSubAgentRowsView()
    private var configuration: Configuration?
    private var isExpanded = false
    private var lastMeasuredHeight: CGFloat = -1

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
        let previousAgentIDs = self.configuration?.agents.map(\.id)
        let shouldResetExpansion = previousAgentIDs != configuration.agents.map(\.id)
        self.configuration = configuration
        if shouldResetExpansion {
            isExpanded = configuration.initiallyExpanded
        }
        rebuild()
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else {
            return
        }
        isExpanded = expanded
        rebuild()
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
        headerView.translatesAutoresizingMaskIntoConstraints = true
        singleAgentContentView.translatesAutoresizingMaskIntoConstraints = true
        nestedAgentsView.translatesAutoresizingMaskIntoConstraints = true
        headerView.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        singleAgentContentView.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        nestedAgentsView.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        singleAgentContentView.onOpenMarkdownLink = onOpenMarkdownLink
        nestedAgentsView.onOpenMarkdownLink = onOpenMarkdownLink
        addSubview(headerView)
    }

    private func rebuild() {
        guard let configuration else {
            return
        }

        singleAgentContentView.removeFromSuperview()
        nestedAgentsView.removeFromSuperview()
        headerView.onToggle = { [weak self] in
            guard let self else {
                return
            }
            self.setExpanded(!self.isExpanded)
        }
        headerView.configure(
            .init(
                summary: headerSummary(for: configuration.agents),
                leadingIcon: .disclosure(isExpanded: isExpanded),
                phase: aggregateStatusPhase(for: configuration.agents),
                typography: configuration.typography,
                bottomPadding: isExpanded ? 0 : transcriptToolRowVerticalPadding
            )
        )

        guard isExpanded else {
            return
        }

        if configuration.agents.count == 1, let agent = configuration.agents.first {
            addSubview(singleAgentContentView)
            singleAgentContentView.onOpenMarkdownLink = onOpenMarkdownLink
            singleAgentContentView.configure(.init(agent: agent, typography: configuration.typography))
        } else {
            addSubview(nestedAgentsView)
            nestedAgentsView.onOpenMarkdownLink = onOpenMarkdownLink
            nestedAgentsView.configure(.init(agents: configuration.agents, typography: configuration.typography))
        }
    }

    private func layoutContent() {
        guard let configuration else {
            return
        }
        let width = max(bounds.width, 0)
        headerView.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude / 2)
        headerView.layoutSubtreeIfNeeded()
        headerView.frame.size.height = headerView.intrinsicContentSize.height

        guard isExpanded else {
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
        invalidateTranscriptHeight(force: true)
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

@MainActor
final class AppKitSubAgentExpandedContentView: NSView {
    struct Configuration: Equatable {
        let agent: SubAgentEntry
        let typography: TranscriptTypography
    }

    var onHeightInvalidated: (() -> Void)?
    var onOpenMarkdownLink: ((URL) -> Void)? {
        didSet {
            toolsView.onOpenMarkdownLink = onOpenMarkdownLink
        }
    }

    private let toolsView = AppKitTranscriptNestedToolRowsView()
    private let resultView = AppKitTranscriptDetailCodeBlockView()
    private var configuration: Configuration?
    private var lastMeasuredHeight: CGFloat = -1

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
        guard self.configuration != configuration else {
            return
        }
        self.configuration = configuration
        rebuild()
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    override func layout() {
        layoutContent()
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        toolsView.translatesAutoresizingMaskIntoConstraints = true
        resultView.translatesAutoresizingMaskIntoConstraints = true
        toolsView.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        resultView.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        toolsView.onOpenMarkdownLink = onOpenMarkdownLink
    }

    private func rebuild() {
        guard let configuration else {
            return
        }

        toolsView.removeFromSuperview()
        resultView.removeFromSuperview()
        if !configuration.agent.tools.isEmpty {
            addSubview(toolsView)
            toolsView.onOpenMarkdownLink = onOpenMarkdownLink
            toolsView.configure(.init(tools: configuration.agent.tools, typography: configuration.typography))
        }

        if let result = configuration.agent.result,
           !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addSubview(resultView)
            resultView.configure(.init(title: "Result", content: result, typography: configuration.typography))
        }
    }

    private func layoutContent() {
        guard let configuration else {
            return
        }
        var currentY: CGFloat = 0
        let width = max(bounds.width, 0)

        if toolsView.superview != nil {
            toolsView.frame = NSRect(x: 0, y: currentY, width: width, height: CGFloat.greatestFiniteMagnitude / 2)
            toolsView.layoutSubtreeIfNeeded()
            toolsView.frame.size.height = toolsView.intrinsicContentSize.height
            currentY = toolsView.frame.maxY + 12
        }

        if resultView.superview != nil {
            let resultTopSpacing = configuration.agent.tools.isEmpty ? transcriptToolExpandedContentTopSpacing : 0
            resultView.frame = NSRect(
                x: transcriptToolDetailLeadingInset,
                y: currentY + resultTopSpacing,
                width: max(width - transcriptToolDetailLeadingInset, 0),
                height: CGFloat.greatestFiniteMagnitude / 2
            )
            resultView.layoutSubtreeIfNeeded()
            resultView.frame.size.height = resultView.intrinsicContentSize.height
        }
    }

    private func measuredHeight() -> CGFloat {
        guard let configuration else {
            return 0
        }
        var height: CGFloat = 0
        if toolsView.superview != nil {
            height += toolsView.intrinsicContentSize.height
        }
        if resultView.superview != nil {
            if height > 0 {
                height += 12
            } else if configuration.agent.tools.isEmpty {
                height += transcriptToolExpandedContentTopSpacing
            }
            height += resultView.intrinsicContentSize.height
            height += toolExpandedContentBottomSpacing
        }
        return ceil(height)
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

extension SubAgentEntry {
    var appKitHasFailedTool: Bool {
        tools.contains(where: \.isError)
    }
}
