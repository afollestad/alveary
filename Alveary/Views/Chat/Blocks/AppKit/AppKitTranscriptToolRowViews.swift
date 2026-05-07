@preconcurrency import AppKit
import Foundation

@MainActor
final class AppKitTranscriptInlineToolRowView: NSView {
    struct Configuration: Equatable {
        let tool: ToolEntry
        let initiallyExpanded: Bool
        let typography: TranscriptTypography

        init(
            tool: ToolEntry,
            initiallyExpanded: Bool = false,
            typography: TranscriptTypography = TranscriptTypography()
        ) {
            self.tool = tool
            self.initiallyExpanded = initiallyExpanded
            self.typography = typography
        }
    }

    var onHeightInvalidated: (() -> Void)?
    var onExpansionChanged: ((Bool) -> Void)?
    var onOpenMarkdownLink: ((URL) -> Void)? {
        didSet {
            detailsView.onOpenMarkdownLink = onOpenMarkdownLink
        }
    }

    private let headerView = AppKitTranscriptToolHeaderRowView()
    private let detailsView = AppKitTranscriptToolDetailsView()
    private var configuration: Configuration?
    private var isExpanded = false
    private var detailsPrewarmTask: Task<Void, Never>?
    private var prewarmedDetailsConfiguration: AppKitTranscriptToolDetailsView.Configuration?
    private var isPrewarmingDetails = false
    private var lastMeasuredHeight: CGFloat = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    deinit { detailsPrewarmTask?.cancel() }

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
        let previousToolID = self.configuration?.tool.id
        let shouldResetExpansion = previousToolID != configuration.tool.id
        let shouldRebuild = shouldResetExpansion ||
            previousConfiguration?.tool != configuration.tool ||
            previousConfiguration?.typography != configuration.typography
        self.configuration = configuration
        if shouldResetExpansion {
            isExpanded = configuration.tool.name == "Skill" ? false : configuration.initiallyExpanded
        }
        // Local expansion changes echo back through SwiftUI as persisted
        // `initiallyExpanded`; avoid rebuilding the already-updated row mid-animation.
        guard shouldRebuild else {
            return
        }
        rebuild()
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    func setExpanded(_ expanded: Bool) {
        guard configuration?.tool.name != "Skill",
              isExpanded != expanded else {
            return
        }
        isExpanded = expanded
        if expanded {
            detailsPrewarmTask?.cancel()
            detailsPrewarmTask = nil
        }
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
        headerView.translatesAutoresizingMaskIntoConstraints = true
        detailsView.translatesAutoresizingMaskIntoConstraints = true
        headerView.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        detailsView.onHeightInvalidated = { [weak self] in
            guard let self, self.isExpanded, !self.isPrewarmingDetails else { return }
            self.childHeightInvalidated()
        }
        detailsView.onOpenMarkdownLink = onOpenMarkdownLink
        addSubview(headerView)
    }

    private func rebuild() {
        guard let configuration else {
            return
        }
        let canExpand = configuration.tool.name != "Skill"
        headerView.onToggle = canExpand ? { [weak self] in
            guard let self else {
                return
            }
            self.setExpanded(!self.isExpanded)
        } : nil
        headerView.configure(
            .init(
                summary: configuration.tool.transcriptDisplaySummary,
                leadingIcon: leadingIconKind(for: configuration.tool, isExpanded: isExpanded),
                phase: configuration.tool.transcriptStatusPhase,
                typography: configuration.typography,
                bottomPadding: isExpanded ? 0 : transcriptToolRowVerticalPadding
            )
        )
        if isExpanded {
            if detailsView.superview == nil {
                addSubview(detailsView)
            }
            configureDetailsView(.init(tool: configuration.tool, typography: configuration.typography))
        } else {
            detailsView.removeFromSuperview()
            scheduleDetailsPrewarm(for: configuration)
        }
    }

    private func layoutContent() {
        let width = max(bounds.width, 0)
        headerView.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude / 2)
        headerView.layoutSubtreeIfNeeded()
        headerView.frame.size.height = headerView.intrinsicContentSize.height
        guard isExpanded else {
            return
        }
        let detailsWidth = max(width - transcriptToolDetailLeadingInset - transcriptToolDetailTrailingInset, 0)
        detailsView.frame = NSRect(
            x: transcriptToolDetailLeadingInset,
            y: headerView.frame.maxY + transcriptToolExpandedContentTopSpacing,
            width: detailsWidth,
            height: CGFloat.greatestFiniteMagnitude / 2
        )
        detailsView.layoutSubtreeIfNeeded()
        detailsView.frame.size.height = detailsView.intrinsicContentSize.height
    }

    private func measuredHeight() -> CGFloat {
        let headerHeight = headerView.frame.height > 0 ? headerView.frame.height : headerView.intrinsicContentSize.height
        guard isExpanded else {
            return ceil(headerHeight)
        }
        let detailsHeight = detailsView.frame.height > 0 ? detailsView.frame.height : detailsView.intrinsicContentSize.height
        return ceil(headerHeight + transcriptToolExpandedContentTopSpacing + detailsHeight + toolExpandedContentBottomSpacing)
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

    private func configureDetailsView(_ detailsConfiguration: AppKitTranscriptToolDetailsView.Configuration) {
        detailsView.configure(detailsConfiguration)
        prewarmedDetailsConfiguration = detailsConfiguration
    }

    private func scheduleDetailsPrewarm(for configuration: Configuration) {
        guard configuration.tool.name != "Skill" else {
            return
        }
        let detailsConfiguration = AppKitTranscriptToolDetailsView.Configuration(
            tool: configuration.tool,
            typography: configuration.typography
        )
        guard prewarmedDetailsConfiguration != detailsConfiguration else {
            return
        }
        detailsPrewarmTask?.cancel()
        detailsPrewarmTask = Task { @MainActor [weak self, configuration, detailsConfiguration] in
            await Task.yield()
            guard let self,
                  !Task.isCancelled,
                  self.configuration == configuration,
                  !self.isExpanded else {
                return
            }
            self.isPrewarmingDetails = true
            defer { self.isPrewarmingDetails = false }
            self.configureDetailsView(detailsConfiguration)
            self.prewarmDetailsLayoutIfPossible()
        }
    }

    private func prewarmDetailsLayoutIfPossible() {
        let detailsWidth = max(bounds.width - transcriptToolDetailLeadingInset - transcriptToolDetailTrailingInset, 0)
        guard detailsWidth > 0 else {
            return
        }
        detailsView.frame = NSRect(
            x: transcriptToolDetailLeadingInset,
            y: headerView.frame.maxY + transcriptToolExpandedContentTopSpacing,
            width: detailsWidth,
            height: CGFloat.greatestFiniteMagnitude / 2
        )
        detailsView.layoutSubtreeIfNeeded()
        detailsView.frame.size.height = detailsView.intrinsicContentSize.height
    }

    private func leadingIconKind(for tool: ToolEntry, isExpanded: Bool) -> TranscriptToolLeadingIconKind {
        switch tool.name {
        case "Bash":
            return .bash
        case "Skill":
            return .symbol(systemName: "book")
        default:
            return .disclosure(isExpanded: isExpanded)
        }
    }
}

@MainActor
final class AppKitTranscriptToolGroupView: NSView {
    struct Configuration: Equatable {
        let tools: [ToolEntry]
        let initiallyExpanded: Bool
        let typography: TranscriptTypography

        init(
            tools: [ToolEntry],
            initiallyExpanded: Bool = false,
            typography: TranscriptTypography = TranscriptTypography()
        ) {
            self.tools = tools
            self.initiallyExpanded = initiallyExpanded
            self.typography = typography
        }
    }

    var onHeightInvalidated: (() -> Void)?
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

    private let headerView = AppKitTranscriptToolHeaderRowView()
    private let singleToolRow = AppKitTranscriptInlineToolRowView()
    private let nestedRowsView = AppKitTranscriptNestedToolRowsView()
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
        let previousConfiguration = self.configuration
        let previousIDs = self.configuration?.tools.map(\.id)
        let shouldResetExpansion = previousIDs != configuration.tools.map(\.id)
        let shouldRebuild = shouldResetExpansion ||
            previousConfiguration?.tools != configuration.tools ||
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
        headerView.translatesAutoresizingMaskIntoConstraints = true
        singleToolRow.translatesAutoresizingMaskIntoConstraints = true
        nestedRowsView.translatesAutoresizingMaskIntoConstraints = true
        headerView.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        singleToolRow.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        nestedRowsView.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        singleToolRow.onOpenMarkdownLink = onOpenMarkdownLink
        singleToolRow.onExpansionChanged = onExpansionChanged
        nestedRowsView.onOpenMarkdownLink = onOpenMarkdownLink
    }

    private func rebuild() {
        guard let configuration else {
            return
        }

        subviews.forEach { $0.removeFromSuperview() }
        guard !configuration.tools.isEmpty else {
            return
        }
        if configuration.tools.count <= 1, let only = configuration.tools.first {
            addSubview(singleToolRow)
            singleToolRow.onOpenMarkdownLink = onOpenMarkdownLink
            singleToolRow.onExpansionChanged = onExpansionChanged
            singleToolRow.configure(
                .init(tool: only, initiallyExpanded: isExpanded, typography: configuration.typography)
            )
            return
        }

        addSubview(headerView)
        headerView.onToggle = { [weak self] in
            guard let self else {
                return
            }
            self.setExpanded(!self.isExpanded)
        }
        headerView.configure(
            .init(
                summary: summary(for: configuration.tools),
                leadingIcon: .disclosure(isExpanded: isExpanded),
                phase: aggregateStatusPhase(for: configuration.tools),
                debounceStatus: true,
                typography: configuration.typography,
                bottomPadding: isExpanded ? 0 : transcriptToolRowVerticalPadding
            )
        )

        if isExpanded {
            addSubview(nestedRowsView)
            nestedRowsView.onOpenMarkdownLink = onOpenMarkdownLink
            nestedRowsView.configure(.init(tools: configuration.tools, typography: configuration.typography))
        }
    }

    private func layoutContent() {
        guard let configuration else {
            return
        }
        let width = max(bounds.width, 0)
        guard !configuration.tools.isEmpty else {
            return
        }
        if configuration.tools.count <= 1 {
            singleToolRow.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude / 2)
            singleToolRow.layoutSubtreeIfNeeded()
            singleToolRow.frame.size.height = singleToolRow.intrinsicContentSize.height
            return
        }

        headerView.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude / 2)
        headerView.layoutSubtreeIfNeeded()
        headerView.frame.size.height = headerView.intrinsicContentSize.height

        guard isExpanded else {
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
    }

    private func measuredHeight() -> CGFloat {
        guard let configuration else {
            return 0
        }
        guard !configuration.tools.isEmpty else {
            return 0
        }
        if configuration.tools.count <= 1 {
            return ceil(singleToolRow.frame.height > 0 ? singleToolRow.frame.height : singleToolRow.intrinsicContentSize.height)
        }
        let headerHeight = headerView.frame.height > 0 ? headerView.frame.height : headerView.intrinsicContentSize.height
        guard isExpanded else {
            return ceil(headerHeight)
        }
        let nestedHeight = nestedRowsView.frame.height > 0 ? nestedRowsView.frame.height : nestedRowsView.intrinsicContentSize.height
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
        invalidateTranscriptHeight(force: true)
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
