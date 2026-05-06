@preconcurrency import AppKit
import Foundation
import QuartzCore

private let collapsedMaxHeight: CGFloat = 260
private let collapseFadeHeight: CGFloat = 56
private let controlClearance: CGFloat = 8
private let controlSpacing: CGFloat = 4
private let toggleMinHeight: CGFloat = 24

private struct TextBubbleLayoutMetrics {
    let bubbleFrame: NSRect
    let markdownClipFrame: NSRect
    let markdownFrame: NSRect
    let overflows: Bool
    let isCollapsed: Bool
}

/// Native transcript bubble row that owns markdown layout, expansion, retry
/// footer, and height invalidation without relying on SwiftUI lazy-list
/// measurement/recycling behavior.
@MainActor
final class AppKitTranscriptTextBubbleRowView: NSView {
    struct Configuration: Equatable {
        let id: String?
        let role: Role
        let markdown: String
        let bubbleMaxWidth: CGFloat
        let typography: AppKitMarkdownTypography
        let showsRetry: Bool
        let initiallyExpanded: Bool

        init(
            id: String? = nil,
            role: Role,
            markdown: String,
            bubbleMaxWidth: CGFloat = .infinity,
            typography: AppKitMarkdownTypography = .default,
            showsRetry: Bool = false,
            initiallyExpanded: Bool = false
        ) {
            self.id = id
            self.role = role
            self.markdown = markdown
            self.bubbleMaxWidth = bubbleMaxWidth
            self.typography = typography
            self.showsRetry = showsRetry
            self.initiallyExpanded = initiallyExpanded
        }
    }

    enum Role: Equatable {
        case user
        case assistant
    }

    var onHeightInvalidated: (() -> Void)?
    var onExpansionChanged: ((Bool) -> Void)?
    var onRetry: (() -> Void)?
    var onOpenMarkdownLink: ((URL) -> Void)? {
        didSet {
            markdownView?.onOpenLink = onOpenMarkdownLink
        }
    }

    private(set) var bubbleView = AppKitFlippedDynamicColorView()
    private(set) var markdownClipView = AppKitFlippedDynamicColorView()
    private(set) var collapsedFadeMask = CAGradientLayer()
    private(set) var expansionButton = AppKitTranscriptHeaderToggleButton()
    private let retryStatusField = NSTextField(labelWithString: "Not sent")
    private let retryButton = NSButton(title: "Retry", target: nil, action: nil)
    private var markdownView: AppKitMarkdownView?
    private var configuration: Configuration?
    private var isExpanded = false
    private var shouldAnimateExpansionLayout = false
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
        let previousID = self.configuration?.id
        let previousInitiallyExpanded = self.configuration?.initiallyExpanded
        let shouldResetExpansion = previousID != configuration.id
        guard self.configuration != configuration else {
            return
        }
        self.configuration = configuration
        if shouldResetExpansion {
            isExpanded = configuration.initiallyExpanded
        } else if previousInitiallyExpanded != configuration.initiallyExpanded {
            isExpanded = configuration.initiallyExpanded
        }
        rebuildMarkdownView()
        updateBubbleAppearance()
        retryStatusField.font = retryStatusFont(for: configuration.typography)
        updateExpansionButton()
        updateRetryVisibility()
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    override func layout() {
        layoutBubble()
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBubbleAppearance()
        updateExpansionButton()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = chatBubbleCornerRadius
        addSubview(bubbleView)

        markdownClipView.wantsLayer = true
        markdownClipView.layer?.masksToBounds = true
        bubbleView.addSubview(markdownClipView)
        collapsedFadeMask.colors = [
            NSColor.black.cgColor,
            NSColor.black.cgColor,
            NSColor.black.withAlphaComponent(0).cgColor
        ]

        expansionButton.isBordered = false
        expansionButton.target = self
        expansionButton.action = #selector(toggleExpansion)
        expansionButton.imagePosition = .imageLeading
        expansionButton.imageHugsTitle = true
        expansionButton.setButtonType(.momentaryPushIn)
        expansionButton.isHidden = true
        bubbleView.addSubview(expansionButton)

        retryStatusField.font = TranscriptTypography().nsFont(.caption)
        retryStatusField.textColor = .secondaryLabelColor
        retryStatusField.isHidden = true
        addSubview(retryStatusField)

        retryButton.controlSize = .small
        retryButton.bezelStyle = .rounded
        retryButton.target = self
        retryButton.action = #selector(retryButtonClicked)
        retryButton.isHidden = true
        addSubview(retryButton)
    }

    private func rebuildMarkdownView() {
        markdownView?.removeFromSuperview()
        guard let configuration else {
            markdownView = nil
            return
        }

        let markdownView = AppKitMarkdownView(
            document: document(for: configuration),
            inlineCodeStyle: inlineCodeStyle(for: configuration.role),
            typography: configuration.typography,
            onOpenLink: onOpenMarkdownLink
        )
        markdownView.translatesAutoresizingMaskIntoConstraints = true
        markdownView.onHeightInvalidated = { [weak self] in
            self?.invalidateTranscriptHeight(force: true)
        }
        markdownClipView.addSubview(markdownView)
        self.markdownView = markdownView
    }

    private func document(for configuration: Configuration) -> AppMarkdownDocument {
        let composerChipProvider: ((String) -> [AppTextEditorChip])?
        if configuration.role == .user {
            composerChipProvider = ChatInputFieldTextSupport.composerTextChips(in:)
        } else {
            composerChipProvider = nil
        }

        return AppMarkdownDocumentCache.document(
            markdown: configuration.markdown,
            context: AppMarkdownDocumentCacheContext(
                baseURL: nil,
                inlineCodeStyle: inlineCodeStyle(for: configuration.role),
                composerChipMode: configuration.role == .user ? .composer : .none,
                taskStateScope: configuration.id
            )
        ) {
            AppMarkdownParser(
                composerChipProvider: composerChipProvider
            )
            .documentPreservingSource(for: configuration.markdown)
        }
    }

    private func layoutBubble() {
        guard let configuration, bounds.width > 0 else {
            return
        }

        let metrics = layoutMetrics(for: configuration)
        let shouldAnimateLayout = shouldAnimateExpansionLayout && window != nil
        shouldAnimateExpansionLayout = false
        expansionButton.isHidden = !metrics.overflows
        updateExpansionButton()
        applyBubbleLayout(metrics, animated: shouldAnimateLayout)
        layoutRetryFooter(bubbleFrame: bubbleView.frame, configuration: configuration)
    }

    private func layoutMetrics(for configuration: Configuration) -> TextBubbleLayoutMetrics {
        let width = bubbleWidth(for: configuration)
        let markdownWidth = max(width - (chatBubbleHorizontalPadding * 2), 0)
        let fullMarkdownHeight = preparedMarkdownMeasurement(for: markdownWidth)?.contentHeight
            ?? measuredMarkdownHeight(for: markdownWidth)
        let overflows = isOverflowing(markdownHeight: fullMarkdownHeight)
        let visibleMarkdownHeight = overflows && !isExpanded ? min(fullMarkdownHeight, collapsedMaxHeight) : fullMarkdownHeight
        let toggleHeight = overflows ? max(toggleMinHeight, ceil(expansionButton.fittingSize.height)) : 0
        let height = visibleMarkdownHeight + (chatVerticalPadding * 2) + (overflows ? controlClearance + controlSpacing + toggleHeight : 0)
        let originX = configuration.role == .user ? max(bounds.width - width, 0) : 0
        return TextBubbleLayoutMetrics(
            bubbleFrame: NSRect(x: originX, y: 0, width: width, height: height),
            markdownClipFrame: NSRect(
                x: chatBubbleHorizontalPadding,
                y: chatVerticalPadding,
                width: markdownWidth,
                height: visibleMarkdownHeight
            ),
            markdownFrame: NSRect(x: 0, y: 0, width: markdownWidth, height: fullMarkdownHeight),
            overflows: overflows,
            isCollapsed: overflows && !isExpanded
        )
    }

    private func applyBubbleLayout(_ metrics: TextBubbleLayoutMetrics, animated: Bool) {
        setFrame(
            metrics.bubbleFrame,
            for: bubbleView,
            animated: animated
        )
        setFrame(metrics.markdownClipFrame, for: markdownClipView, animated: animated)
        if let markdownView {
            setFrame(metrics.markdownFrame, for: markdownView, animated: animated)
        }
        updateCollapsedFadeMask(isCollapsed: metrics.isCollapsed)
        if metrics.overflows {
            setFrame(expansionButtonFrame(markdownClipFrame: metrics.markdownClipFrame), for: expansionButton, animated: animated)
        } else {
            expansionButton.frame = .zero
        }
    }

    private func expansionButtonFrame(markdownClipFrame: NSRect) -> NSRect {
        let buttonSize = expansionButton.fittingSize
        return NSRect(
            x: chatBubbleHorizontalPadding,
            // SwiftUI stacked the 8pt content clearance and 4pt VStack spacing
            // above Show more/less, leaving only the normal bubble padding below it.
            y: markdownClipFrame.maxY + controlClearance + controlSpacing,
            width: ceil(buttonSize.width),
            height: max(toggleMinHeight, ceil(buttonSize.height))
        )
    }

    private func measuredMarkdownHeight(for markdownWidth: CGFloat) -> CGFloat {
        // Measure against the current content height rather than an arbitrary
        // giant probe frame. Some AppKit markdown children pin to their container
        // for width/layout, and a huge temporary height can leak into the rendered
        // bubble before the transcript container caches the row height.
        let measurementHeight = max(markdownView?.intrinsicContentSize.height ?? 0, 120)
        markdownView?.frame = NSRect(x: 0, y: 0, width: markdownWidth, height: measurementHeight)
        markdownView?.layoutSubtreeIfNeeded()
        return markdownView?.intrinsicContentSize.height ?? 0
    }

    private func bubbleWidth(for configuration: Configuration) -> CGFloat {
        let availableWidth = max(bounds.width, 0)
        let maxWidth = maxBubbleWidth(for: configuration, availableWidth: availableWidth)

        // SwiftUI used `.frame(maxWidth:)`, so short bubbles hugged their
        // rendered markdown and only grew to the cap when text needed to wrap.
        let maxContentWidth = max(maxWidth - (chatBubbleHorizontalPadding * 2), 0)
        let naturalContentWidth = preparedMarkdownMeasurement(for: maxContentWidth)?.naturalContentWidth
            ?? naturalMarkdownWidth(constrainedTo: maxContentWidth)
        let naturalBubbleWidth = naturalContentWidth + (chatBubbleHorizontalPadding * 2)
        return min(max(naturalBubbleWidth, 0), maxWidth)
    }

    private func maxBubbleWidth(for configuration: Configuration, availableWidth: CGFloat) -> CGFloat {
        switch configuration.role {
        case .user:
            return min(userBubbleMaxWidth, max(availableWidth - userBubbleLeadingClearance, 0))
        case .assistant:
            let cap = configuration.bubbleMaxWidth.isFinite ? configuration.bubbleMaxWidth : availableWidth
            return min(max(cap, 0), availableWidth)
        }
    }

    private func preparedMarkdownMeasurement(for markdownWidth: CGFloat) -> AppKitMarkdownLayoutMeasurement? {
        guard let configuration else {
            return nil
        }
        let inlineCodeStyle = inlineCodeStyle(for: configuration.role)
        return TextBubblePreparedMeasurement.measurement(
            .init(
                configuration: configuration,
                isExpanded: isExpanded,
                markdownWidth: markdownWidth,
                inlineCodeStyle: inlineCodeStyle,
                document: document(for: configuration),
                appearance: effectiveAppearance
            )
        )
    }

    private func naturalMarkdownWidth(constrainedTo maxContentWidth: CGFloat) -> CGFloat {
        guard let markdownView else {
            return 0
        }

        let textWidths = markdownView.transcriptMarkdownTextViews.map { textView in
            textView.transcriptNaturalTextWidth(constrainedTo: maxContentWidth)
        }
        let viewWidths = markdownView.transcriptNonTextMarkdownViews.map { view in
            if let tableView = view as? AppKitMarkdownTableView {
                return tableView.naturalViewportWidth(constrainedTo: maxContentWidth)
            }
            return view.fittingSize.width
        }
        return ceil(max((textWidths + viewWidths).max() ?? 0, 0))
    }

    private func updateBubbleAppearance() {
        guard let configuration else {
            return
        }
        switch configuration.role {
        case .user:
            bubbleView.setLayerFillColor(AppAccentFill.primaryNSColor)
        case .assistant:
            bubbleView.setLayerFillColor(.secondaryLabelColor, alpha: 0.08)
        }
    }

    private func updateRetryVisibility() {
        let isVisible = configuration?.showsRetry == true && configuration?.role == .user && onRetry != nil
        retryStatusField.isHidden = !isVisible
        retryButton.isHidden = !isVisible
    }

    private func updateExpansionButton() {
        let title = isExpanded ? "Show less" : "Show more"
        expansionButton.title = title
        expansionButton.font = expansionToggleFont()
        expansionButton.symbolName = isExpanded ? "chevron.up" : "chevron.down"
        expansionButton.setAccessibilityLabel(title)
    }

    private func isOverflowing(markdownHeight: CGFloat) -> Bool {
        // AppKit has an exact rendered height here; the SwiftUI raw-markdown
        // heuristic can falsely collapse short lists with several source lines.
        markdownHeight > collapsedMaxHeight + 1
    }

    private func layoutRetryFooter(bubbleFrame: NSRect, configuration: Configuration) {
        guard configuration.showsRetry,
              configuration.role == .user,
              onRetry != nil else {
            retryStatusField.frame = .zero
            retryButton.frame = .zero
            return
        }

        retryStatusField.sizeToFit()
        retryButton.sizeToFit()
        let spacing: CGFloat = 8
        let topSpacing: CGFloat = 6
        let footerY = bubbleFrame.maxY + topSpacing
        let footerHeight = max(retryStatusField.frame.height, retryButton.frame.height)
        let buttonX = bounds.width - retryButton.frame.width
        retryButton.frame.origin = NSPoint(x: buttonX, y: footerY)
        retryStatusField.frame.origin = NSPoint(
            x: buttonX - spacing - retryStatusField.frame.width,
            y: footerY + max(0, (footerHeight - retryStatusField.frame.height) / 2)
        )
    }

    private func updateCollapsedFadeMask(isCollapsed: Bool) {
        guard isCollapsed else {
            markdownClipView.layer?.mask = nil
            return
        }

        // SwiftUI used a bottom alpha mask for collapsed long bubbles. The
        // native row owns the same fade explicitly so clipped transcript text
        // does not end abruptly above the Show more control.
        let fadeStart = max(markdownClipView.bounds.height - collapseFadeHeight, 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        collapsedFadeMask.frame = markdownClipView.bounds
        collapsedFadeMask.startPoint = CGPoint(x: 0.5, y: 0)
        collapsedFadeMask.endPoint = CGPoint(x: 0.5, y: 1)
        collapsedFadeMask.locations = [
            0,
            NSNumber(value: Double(fadeStart / max(markdownClipView.bounds.height, 1))),
            1
        ]
        markdownClipView.layer?.mask = collapsedFadeMask
        CATransaction.commit()
    }

    // AppKit rows report their own height changes so the scroll container can
    // preserve anchors without relying on SwiftUI geometry preferences.
    private func invalidateTranscriptHeight(force: Bool) {
        let newHeight = measuredHeight()
        guard force || abs(newHeight - lastMeasuredHeight) > 0.5 else {
            return
        }
        lastMeasuredHeight = newHeight
        invalidateIntrinsicContentSize()
        onHeightInvalidated?()
    }

    private func measuredHeight() -> CGFloat {
        let bubbleHeight: CGFloat
        if bubbleView.frame.height > 0 {
            bubbleHeight = bubbleView.frame.height
        } else {
            bubbleHeight = (markdownView?.intrinsicContentSize.height ?? 0) + (chatVerticalPadding * 2)
        }
        let retryHeight = retryButton.isHidden ? 0 : 6 + max(retryStatusField.frame.height, retryButton.frame.height)
        return ceil(bubbleHeight + retryHeight)
    }

    private func setFrame(_ frame: NSRect, for view: NSView, animated: Bool) {
        guard animated, view.frame != .zero, view.frame != frame else {
            view.frame = frame
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = appExpansionAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            view.animator().frame = frame
        }
    }

    private func expansionToggleFont() -> NSFont {
        let bodySize = configuration?.typography.body.pointSize ?? NSFont.systemFontSize
        return .systemFont(ofSize: max(bodySize - 2, 9), weight: .medium)
    }

    private func retryStatusFont(for typography: AppKitMarkdownTypography) -> NSFont {
        NSFont.systemFont(ofSize: max(typography.body.pointSize - 2, 9))
    }

    @objc
    private func retryButtonClicked() {
        onRetry?()
    }

    @objc
    private func toggleExpansion() {
        isExpanded.toggle()
        shouldAnimateExpansionLayout = true
        needsLayout = true
        invalidateTranscriptHeight(force: true)
        onExpansionChanged?(isExpanded)
    }

}
