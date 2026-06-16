@preconcurrency import AppKit
import Foundation
import QuartzCore

@MainActor
final class AppKitTranscriptPromptUsageRowView: NSView {
    struct Configuration: Equatable {
        let prompt: PromptEntry
        let initiallyExpanded: Bool
        let canExpand: Bool
        let bubbleMaxWidth: CGFloat
        let showsLeadingIcon: Bool
        let typography: TranscriptTypography

        init(
            prompt: PromptEntry,
            initiallyExpanded: Bool = false,
            canExpand: Bool? = nil,
            bubbleMaxWidth: CGFloat = .infinity,
            showsLeadingIcon: Bool = true,
            typography: TranscriptTypography = TranscriptTypography()
        ) {
            self.prompt = prompt
            self.initiallyExpanded = initiallyExpanded
            self.canExpand = canExpand ?? prompt.appKitRendersSubmittedDetails
            self.bubbleMaxWidth = bubbleMaxWidth
            self.showsLeadingIcon = showsLeadingIcon
            self.typography = typography
        }
    }

    var onHeightInvalidated: (() -> Void)?
    var onUserInitiatedHeightChange: (() -> Void)?
    var onExpansionChanged: ((Bool) -> Void)?
    var usesLocalClipAnimationForExpansion = false

    private let clipView = AppKitTranscriptExpandableClipView()
    private let headerView = AppKitTranscriptToolHeaderRowView()
    private let detailsView = AppKitTranscriptPromptUsageDetailsView()
    private var configuration: Configuration?
    private var isExpanded = false
    private var lastMeasuredHeight: CGFloat = -1
    private var localClipAnimationToken = UUID()
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

    var headerVisualCenterY: CGFloat {
        headerView.frame.midY
    }

    func configure(_ configuration: Configuration) {
        let previousConfiguration = self.configuration
        let previousPromptID = self.configuration?.prompt.id
        let shouldResetExpansion = previousPromptID != configuration.prompt.id
        let shouldSyncExpansion = !shouldResetExpansion &&
            previousConfiguration?.initiallyExpanded != configuration.initiallyExpanded &&
            isExpanded != configuration.initiallyExpanded
        let shouldRebuild = shouldResetExpansion ||
            shouldSyncExpansion ||
            previousConfiguration?.prompt != configuration.prompt ||
            previousConfiguration?.canExpand != configuration.canExpand ||
            previousConfiguration?.bubbleMaxWidth != configuration.bubbleMaxWidth ||
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
            guard let self, self.isExpanded else { return }
            self.childHeightInvalidated()
        }
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
                summary: Self.summary(for: configuration.prompt),
                leadingIcon: .question,
                phase: ToolStatusPhase(isError: false, isComplete: configuration.prompt.submittedSummary != nil),
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
            detailsView.configure(.init(prompt: configuration.prompt, typography: configuration.typography))
        } else {
            detailsView.removeFromSuperview()
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
        let maxWidth = configuration.bubbleMaxWidth.isFinite ? configuration.bubbleMaxWidth : availableWidth
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
        return ceil(
            headerHeight +
                transcriptToolExpandedContentTopSpacing +
                detailsView.intrinsicContentSize.height +
                toolExpandedContentBottomSpacing
        )
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

    private static func summary(for prompt: PromptEntry) -> String {
        TranscriptToolGroupSummaryFormatter.promptQuestionSummary(
            count: prompt.questions.count,
            isComplete: prompt.submittedSummary != nil
        )
    }
}

extension AppKitTranscriptPromptUsageRowView: AppKitTranscriptFrameAnimatable {
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
