@preconcurrency import AppKit
import Foundation
import QuartzCore

private let collapsedMaxHeight: CGFloat = 260
private let collapseFadeHeight: CGFloat = 56
let textBubbleControlClearance: CGFloat = 8
let textBubbleControlSpacing: CGFloat = 4
let textBubbleToggleMinHeight: CGFloat = 24

struct TextBubbleLayoutMetrics {
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
        let markdownBaseURL: URL?
        let showsRetry: Bool
        let initiallyExpanded: Bool

        init(
            id: String? = nil,
            role: Role,
            markdown: String,
            bubbleMaxWidth: CGFloat = .infinity,
            typography: AppKitMarkdownTypography = .default,
            markdownBaseURL: URL? = nil,
            showsRetry: Bool = false,
            initiallyExpanded: Bool = false
        ) {
            self.id = id
            self.role = role
            self.markdown = markdown
            self.bubbleMaxWidth = bubbleMaxWidth
            self.typography = typography
            self.markdownBaseURL = markdownBaseURL
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
    var hydratesMarkdownImmediately = true

    private(set) var bubbleView = AppKitFlippedDynamicColorView()
    private(set) var markdownClipView = AppKitFlippedDynamicColorView()
    private(set) var collapsedFadeMask = CAGradientLayer()
    private(set) var expansionButton = AppKitTranscriptHeaderToggleButton()
    private let retryStatusField = NSTextField(labelWithString: "Not sent")
    private let retryButton = NSButton(title: "Retry", target: nil, action: nil)
    var markdownView: AppKitMarkdownView?
    private(set) var configuration: Configuration?
    private(set) var isExpanded = false
    private var lastMeasuredHeight: CGFloat = -1
    var lastLayoutMetrics: TextBubbleLayoutMetrics?
    var synchronizedFrameAnimations: [TextBubbleSynchronizedFrameAnimation] = []
    var isHydratingMarkdownForViewport = false
    var hasMarkdownHeightHandler = false
    var asyncPreparedMarkdown: AsyncPreparedMarkdown?
    var pendingAsyncPreparationKey: AppKitMarkdownPreparedLayoutKey?
    var asyncPreparationGeneration = 0
    var asyncPreparationTask: Task<Void, Never>?
#if DEBUG
    var asyncDocumentLoaderForTesting: ((String, AppMarkdownDocumentCacheContext) async -> AppMarkdownDocument)?
#endif
    // Set only after a prepared layout mismatch; the row then measures the
    // hydrated AppKit view until a new configuration gives the cache another chance.
    var forceHydratedMarkdownMeasurement = false

    deinit {
        asyncPreparationTask?.cancel()
    }

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
        let shouldResetExpansion = previousConfiguration?.id != configuration.id
        guard previousConfiguration != configuration else {
            return
        }
        if let previousConfiguration, previousConfiguration.hasSameRenderedContent(as: configuration) {
            self.configuration = configuration
            guard isExpanded != configuration.initiallyExpanded else {
                updateRetryVisibility()
                return
            }
            isExpanded = configuration.initiallyExpanded
            updateExpansionButton()
            refreshLayoutMetricsForCurrentState()
            updateRetryVisibility()
            needsLayout = true
            invalidateTranscriptHeight(force: false)
            return
        }
        self.configuration = configuration
        lastLayoutMetrics = nil
        forceHydratedMarkdownMeasurement = false
        if shouldResetExpansion {
            isExpanded = configuration.initiallyExpanded
        }
        resetMarkdownView()
        updateBubbleAppearance()
        retryStatusField.font = retryStatusFont(for: configuration.typography)
        updateExpansionButton()
        updateRetryVisibility()
        if hydratesMarkdownImmediately {
            hydrateMarkdownIfNeeded()
        }
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    override func layout() {
        layoutBubble()
        super.layout()
        if !isHydratingMarkdownForViewport {
            installMarkdownHeightInvalidationHandlerIfNeeded()
        }
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

    private func layoutBubble() {
        guard let configuration, bounds.width > 0 else {
            return
        }

        updateExpansionButton()
        let metrics = layoutMetrics(for: configuration)
        lastLayoutMetrics = metrics
        expansionButton.isHidden = !metrics.overflows
        applyBubbleLayout(metrics)
        layoutRetryFooter(bubbleFrame: metrics.bubbleFrame, configuration: configuration)
    }

    private func layoutMetrics(for configuration: Configuration) -> TextBubbleLayoutMetrics {
        let width = bubbleWidth(for: configuration)
        let markdownWidth = max(width - (chatBubbleHorizontalPadding * 2), 0)
        let fullMarkdownHeight = preparedMarkdownMeasurement(for: markdownWidth)?.contentHeight
            ?? measuredMarkdownHeight(for: markdownWidth)
        let overflows = isOverflowing(markdownHeight: fullMarkdownHeight)
        let visibleMarkdownHeight = overflows && !isExpanded ? min(fullMarkdownHeight, collapsedMaxHeight) : fullMarkdownHeight
        let toggleHeight = overflows ? max(textBubbleToggleMinHeight, ceil(expansionButton.fittingSize.height)) : 0
        let height = visibleMarkdownHeight + (chatVerticalPadding * 2) +
            (overflows ? textBubbleControlClearance + textBubbleControlSpacing + toggleHeight : 0)
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

    private func applyBubbleLayout(_ metrics: TextBubbleLayoutMetrics) {
        if !metrics.overflows {
            expansionButton.frame = .zero
        }
        applyFrameUpdates(frameUpdates(for: metrics), animated: false)
        if let markdownView {
            markdownView.maximumImageDisplayWidth = metrics.markdownFrame.width
            validateHydratedMarkdownHeight(markdownView, metrics: metrics)
        }
        updateCollapsedFadeMask(isCollapsed: metrics.isCollapsed)
    }

    func expansionButtonFrame(markdownClipFrame: NSRect) -> NSRect {
        let buttonSize = expansionButton.fittingSize
        return NSRect(
            x: chatBubbleHorizontalPadding,
            // SwiftUI stacked the 8pt content clearance and 4pt VStack spacing
            // above Show more/less, leaving only the normal bubble padding below it.
            y: markdownClipFrame.maxY + textBubbleControlClearance + textBubbleControlSpacing,
            width: ceil(buttonSize.width),
            height: max(textBubbleToggleMinHeight, ceil(buttonSize.height))
        )
    }

    private func measuredMarkdownHeight(for markdownWidth: CGFloat) -> CGFloat {
        hydrateMarkdownIfNeeded()
        // Measure against the current content height rather than an arbitrary
        // giant probe frame. Some AppKit markdown children pin to their container
        // for width/layout, and a huge temporary height can leak into the rendered
        // bubble before the transcript container caches the row height.
        let measurementHeight = max(markdownView?.intrinsicContentSize.height ?? 0, 120)
        markdownView?.maximumImageDisplayWidth = markdownWidth
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
            return min(max(configuration.bubbleMaxWidth.isFinite ? configuration.bubbleMaxWidth : availableWidth, 0), availableWidth)
        }
    }

    private func preparedMarkdownMeasurement(for markdownWidth: CGFloat) -> AppKitMarkdownLayoutMeasurement? {
        guard let configuration, !forceHydratedMarkdownMeasurement else {
            return nil
        }
        let context = preparedMeasurementContext(for: markdownWidth, configuration: configuration)
        if let cached = TextBubblePreparedMeasurement.cachedMeasurement(for: context.key) {
            return cached
        }
        scheduleAsyncMarkdownPreparation(for: context)
        if asyncPreparedMarkdown?.key == context.key, let document = asyncPreparedMarkdown?.document {
            return TextBubblePreparedMeasurement.measurement(context, document: document)
        }
        return TextBubblePreparedMeasurement.measurement(context, document: document(for: configuration))
    }

    private func naturalMarkdownWidth(constrainedTo maxContentWidth: CGFloat) -> CGFloat {
        hydrateMarkdownIfNeeded()
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

    func updateCollapsedFadeMask(isCollapsed: Bool) {
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
    func invalidateTranscriptHeight(force: Bool) {
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
        if let lastLayoutMetrics {
            bubbleHeight = lastLayoutMetrics.bubbleFrame.height
        } else if bubbleView.frame.height > 0 {
            bubbleHeight = bubbleView.frame.height
        } else {
            bubbleHeight = (markdownView?.intrinsicContentSize.height ?? 0) + (chatVerticalPadding * 2)
        }
        let retryHeight = retryButton.isHidden ? 0 : 6 + max(retryStatusField.frame.height, retryButton.frame.height)
        return ceil(bubbleHeight + retryHeight)
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
        updateExpansionButton()
        refreshLayoutMetricsForCurrentState()
        needsLayout = true
        invalidateTranscriptHeight(force: true)
        onExpansionChanged?(isExpanded)
    }

    private func refreshLayoutMetricsForCurrentState() {
        guard let configuration, bounds.width > 0 else {
            return
        }
        lastLayoutMetrics = layoutMetrics(for: configuration)
    }

}

private extension AppKitTranscriptTextBubbleRowView.Configuration {
    func hasSameRenderedContent(as other: Self) -> Bool {
        let sameMaxWidth = bubbleMaxWidth == other.bubbleMaxWidth || abs(bubbleMaxWidth - other.bubbleMaxWidth) <= 0.5
        return id == other.id && role == other.role && markdown == other.markdown &&
            sameMaxWidth && typography == other.typography && markdownBaseURL == other.markdownBaseURL &&
            showsRetry == other.showsRetry
    }
}

struct AsyncPreparedMarkdown {
    let key: AppKitMarkdownPreparedLayoutKey
    let document: AppMarkdownDocument
}
