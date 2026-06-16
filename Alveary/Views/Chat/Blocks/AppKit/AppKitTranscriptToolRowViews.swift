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
        let showsLeadingIcon: Bool
        let typography: TranscriptTypography

        init(
            tool: ToolEntry,
            initiallyExpanded: Bool = false,
            canExpand: Bool? = nil,
            maxWidth: CGFloat = .infinity,
            showsLeadingIcon: Bool = true,
            typography: TranscriptTypography = TranscriptTypography()
        ) {
            self.tool = tool
            self.initiallyExpanded = initiallyExpanded
            self.canExpand = canExpand ?? tool.appKitRendersDetails
            self.maxWidth = maxWidth
            self.showsLeadingIcon = showsLeadingIcon
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
    private var prewarmedDetailsLayoutSignature: PrewarmedDetailsLayoutSignature?
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
        let shouldSyncExpansion = !shouldResetExpansion &&
            previousConfiguration?.initiallyExpanded != configuration.initiallyExpanded &&
            isExpanded != configuration.initiallyExpanded
        let shouldRebuild = shouldResetExpansion ||
            shouldSyncExpansion ||
            previousConfiguration?.tool != configuration.tool ||
            previousConfiguration?.canExpand != configuration.canExpand ||
            previousConfiguration?.maxWidth != configuration.maxWidth ||
            previousConfiguration?.showsLeadingIcon != configuration.showsLeadingIcon ||
            previousConfiguration?.typography != configuration.typography
        self.configuration = configuration
        if shouldResetExpansion {
            isExpanded = configuration.canExpand ? configuration.initiallyExpanded : false
        } else if shouldSyncExpansion {
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
                showsLeadingIcon: configuration.showsLeadingIcon,
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
            if configuration.canExpand {
                scheduleDetailsPrewarm(for: configuration)
            } else {
                clearPrewarmedDetails()
            }
        }
    }

    private func layoutContent() {
        let width = contentWidth(for: configuration)
        headerView.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude / 2)
        headerView.layoutSubtreeIfNeeded()
        headerView.frame.size.height = headerView.intrinsicContentSize.height
        guard isExpanded else {
            if let detailsConfiguration = detailsConfiguration(for: configuration),
               prewarmedDetailsConfiguration == detailsConfiguration {
                prewarmDetailsLayoutIfPossible()
            }
            clipView.updateFrame(width: width, targetHeight: headerView.frame.height)
            return
        }
        let detailsFrame = directDetailsFrame(width: width, originY: headerView.frame.maxY + transcriptToolExpandedContentTopSpacing)
        detailsView.frame = NSRect(
            x: detailsFrame.minX,
            y: detailsFrame.minY,
            width: detailsFrame.width,
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

    private func directDetailsFrame(width: CGFloat, originY: CGFloat) -> NSRect {
        let typography = configuration?.typography ?? TranscriptTypography()
        let metrics = transcriptInlineToolRowMetrics(for: typography)
        let leadingInset = metrics.directDetailLeadingInset(showsLeadingIcon: configuration?.showsLeadingIcon ?? true)
        return NSRect(
            x: leadingInset,
            y: originY,
            width: max(width - leadingInset - metrics.detailTrailingInset, 0),
            height: CGFloat.greatestFiniteMagnitude / 2
        )
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
        prewarmedDetailsLayoutSignature = nil
    }

    private func clearPrewarmedDetails() {
        detailsPrewarmTask?.cancel()
        detailsPrewarmTask = nil
        prewarmedDetailsConfiguration = nil
        prewarmedDetailsLayoutSignature = nil
    }

    private func scheduleDetailsPrewarm(for configuration: Configuration) {
        guard let detailsConfiguration = detailsConfiguration(for: configuration) else {
            clearPrewarmedDetails()
            return
        }
        if prewarmedDetailsConfiguration == detailsConfiguration {
            prewarmDetailsLayoutIfPossible()
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
        let originY = headerView.frame.maxY + transcriptToolExpandedContentTopSpacing
        let detailsFrame = directDetailsFrame(width: width, originY: originY)
        guard detailsFrame.width > 0 else {
            return
        }
        let layoutSignature = PrewarmedDetailsLayoutSignature(
            width: width,
            originY: originY,
            showsLeadingIcon: configuration?.showsLeadingIcon ?? true,
            typography: configuration?.typography ?? TranscriptTypography()
        )
        guard prewarmedDetailsLayoutSignature != layoutSignature else {
            return
        }
        detailsView.frame = NSRect(
            x: detailsFrame.minX,
            y: detailsFrame.minY,
            width: detailsFrame.width,
            height: CGFloat.greatestFiniteMagnitude / 2
        )
        detailsView.layoutSubtreeIfNeeded()
        detailsView.frame.size.height = detailsView.intrinsicContentSize.height
        prewarmedDetailsLayoutSignature = layoutSignature
    }

    private func detailsConfiguration(for configuration: Configuration?) -> AppKitTranscriptToolDetailsView.Configuration? {
        guard let configuration,
              configuration.canExpand else {
            return nil
        }
        return AppKitTranscriptToolDetailsView.Configuration(
            tool: configuration.tool,
            typography: configuration.typography
        )
    }

}

private struct PrewarmedDetailsLayoutSignature: Equatable {
    let width: CGFloat
    let originY: CGFloat
    let showsLeadingIcon: Bool
    let typography: TranscriptTypography
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

    var prewarmedDetailsFrameForTesting: NSRect {
        detailsView.frame
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
        if prewarmedDetailsConfiguration == detailsConfiguration {
            prewarmDetailsLayoutIfPossible()
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
