@preconcurrency import AppKit
import Foundation
import QuartzCore

@MainActor
final class AppKitTranscriptInlineToolRowView: NSView {
    struct Configuration: Equatable {
        let tool: ToolEntry
        let initiallyExpanded: Bool
        let canExpand: Bool
        let maxWidth: CGFloat
        let typography: TranscriptTypography

        init(
            tool: ToolEntry,
            initiallyExpanded: Bool = false,
            canExpand: Bool? = nil,
            maxWidth: CGFloat = .infinity,
            typography: TranscriptTypography = TranscriptTypography()
        ) {
            self.tool = tool
            self.initiallyExpanded = initiallyExpanded
            self.canExpand = canExpand ?? tool.appKitRendersDetails
            self.maxWidth = maxWidth
            self.typography = typography
        }
    }

    var onHeightInvalidated: (() -> Void)?
    var onUserInitiatedHeightChange: (() -> Void)? {
        didSet {
            detailsView.onUserInitiatedHeightChange = onUserInitiatedHeightChange
        }
    }
    var onExpansionChanged: ((Bool) -> Void)?
    var usesLocalClipAnimationForExpansion = false
    var onOpenMarkdownLink: ((URL) -> Void)? {
        didSet {
            detailsView.onOpenMarkdownLink = onOpenMarkdownLink
        }
    }

    private let clipView = AppKitTranscriptExpandableClipView()
    private let headerView = AppKitTranscriptToolHeaderRowView()
    private let detailsView = AppKitTranscriptToolDetailsView()
    private var configuration: Configuration?
    private var isExpanded = false
    private var detailsPrewarmTask: Task<Void, Never>?
    private var prewarmedDetailsConfiguration: AppKitTranscriptToolDetailsView.Configuration?
    private var isPrewarmingDetails = false
    private var lastMeasuredHeight: CGFloat = -1
    private var localClipAnimationToken = UUID()
    private var isBatchingChildHeightInvalidations = false

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
            previousConfiguration?.canExpand != configuration.canExpand ||
            previousConfiguration?.maxWidth != configuration.maxWidth ||
            previousConfiguration?.typography != configuration.typography
        self.configuration = configuration
        if shouldResetExpansion {
            isExpanded = configuration.canExpand ? configuration.initiallyExpanded : false
        } else if !configuration.canExpand {
            isExpanded = false
        }
        // Local expansion changes echo back through SwiftUI as persisted
        // `initiallyExpanded`; avoid rebuilding the already-updated row mid-animation.
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
        let previousHeight = measuredHeight()
        onUserInitiatedHeightChange?()
        isExpanded = expanded
        if expanded {
            detailsPrewarmTask?.cancel()
            detailsPrewarmTask = nil
        }
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

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        clipView.translatesAutoresizingMaskIntoConstraints = true
        headerView.translatesAutoresizingMaskIntoConstraints = true
        detailsView.translatesAutoresizingMaskIntoConstraints = true
        headerView.onHeightInvalidated = { [weak self] in self?.childHeightInvalidated() }
        detailsView.onHeightInvalidated = { [weak self] in
            guard let self, self.isExpanded, !self.isPrewarmingDetails else { return }
            self.childHeightInvalidated()
        }
        detailsView.onOpenMarkdownLink = onOpenMarkdownLink
        addSubview(clipView)
        clipView.addSubview(headerView)
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
                summary: configuration.tool.transcriptDisplaySummary,
                leadingIcon: configuration.tool.transcriptLeadingIconKind,
                phase: configuration.tool.transcriptStatusPhase,
                isExpanded: configuration.canExpand ? isExpanded : nil,
                typography: configuration.typography,
                bottomPadding: isExpanded ? 0 : transcriptInlineToolRowVerticalPadding
            )
        )
        if isExpanded {
            if detailsView.superview == nil {
                clipView.addSubview(detailsView)
            }
            configureDetailsView(.init(tool: configuration.tool, typography: configuration.typography))
        } else {
            detailsView.removeFromSuperview()
            scheduleDetailsPrewarm(for: configuration)
        }
    }

    private func layoutContent() {
        let width = contentWidth(for: configuration)
        headerView.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude / 2)
        headerView.layoutSubtreeIfNeeded()
        headerView.frame.size.height = headerView.intrinsicContentSize.height
        guard isExpanded else {
            clipView.updateFrame(width: width, targetHeight: headerView.frame.height)
            return
        }
        let metrics = transcriptInlineToolRowMetrics(for: configuration?.typography ?? TranscriptTypography())
        let detailsWidth = max(width - metrics.detailLeadingInset - metrics.detailTrailingInset, 0)
        detailsView.frame = NSRect(
            x: metrics.detailLeadingInset,
            y: headerView.frame.maxY + transcriptToolExpandedContentTopSpacing,
            width: detailsWidth,
            height: CGFloat.greatestFiniteMagnitude / 2
        )
        detailsView.layoutSubtreeIfNeeded()
        detailsView.frame.size.height = detailsView.intrinsicContentSize.height
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
        let detailsHeight = detailsView.intrinsicContentSize.height
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
        guard usesLocalClipAnimationForExpansion,
              window != nil,
              bounds.width > 0 else {
            return
        }
        let width = contentWidth(for: configuration)
        let targetHeight = measuredHeight()
        guard previousHeight > 0,
              targetHeight > 0,
              abs(previousHeight - targetHeight) > 0.5 else {
            return
        }
        clipView.prepareVisibleHeightAnimation(from: previousHeight, to: targetHeight, width: width)
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

    private func configureDetailsView(_ detailsConfiguration: AppKitTranscriptToolDetailsView.Configuration) {
        detailsView.configure(detailsConfiguration)
        prewarmedDetailsConfiguration = detailsConfiguration
    }

    private func scheduleDetailsPrewarm(for configuration: Configuration) {
        guard configuration.canExpand else {
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
        let width = contentWidth(for: configuration)
        let metrics = transcriptInlineToolRowMetrics(for: configuration?.typography ?? TranscriptTypography())
        let detailsWidth = max(width - metrics.detailLeadingInset - metrics.detailTrailingInset, 0)
        guard detailsWidth > 0 else {
            return
        }
        detailsView.frame = NSRect(
            x: metrics.detailLeadingInset,
            y: headerView.frame.maxY + transcriptToolExpandedContentTopSpacing,
            width: detailsWidth,
            height: CGFloat.greatestFiniteMagnitude / 2
        )
        detailsView.layoutSubtreeIfNeeded()
        detailsView.frame.size.height = detailsView.intrinsicContentSize.height
    }

}

extension AppKitTranscriptInlineToolRowView: AppKitTranscriptFrameAnimatable {
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

#if DEBUG
extension AppKitTranscriptInlineToolRowView {
    var prewarmedDetailsRenderedTextForTesting: String {
        detailsView.renderedTextForPrewarmTesting
    }

    var prewarmedDetailsToolForTesting: ToolEntry? {
        prewarmedDetailsConfiguration?.tool
    }

    func prewarmDetailsIfNeededForTesting() {
        guard let configuration,
              configuration.canExpand,
              !isExpanded else {
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
        detailsPrewarmTask = nil
        isPrewarmingDetails = true
        configureDetailsView(detailsConfiguration)
        prewarmDetailsLayoutIfPossible()
        isPrewarmingDetails = false
    }
}

private extension NSView {
    var renderedTextForPrewarmTesting: String {
        subviews.flatMap { child -> [String] in
            let childText = child.renderedTextForPrewarmTesting
            var values = childText.isEmpty ? [] : [childText]
            if let field = child as? NSTextField {
                values.insert(field.stringValue, at: 0)
            }
            if let markdownText = child as? AppKitMarkdownTextView {
                values.insert(markdownText.string, at: 0)
            }
            return values
        }
        .joined(separator: "\n")
    }
}
#endif
