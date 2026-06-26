@preconcurrency import AppKit
import BlockInputKit
import Foundation
import QuartzCore

let collapsedMaxHeight: CGFloat = 260
private let collapseFadeHeight: CGFloat = 56
let textBubbleControlClearance: CGFloat = 8
let textBubbleControlSpacing: CGFloat = 4
let textBubbleToggleMinHeight: CGFloat = 24
let textBubbleImageStripBubbleSpacing: CGFloat = 6

struct TextBubbleLayoutMetrics {
    let imageStripFrame: NSRect?
    let bubbleFrame: NSRect
    let hasBubble: Bool
    let markdownClipFrame: NSRect
    let markdownFrame: NSRect
    let overflows: Bool
    let isCollapsed: Bool

    var contentHeight: CGFloat {
        max(imageStripFrame?.maxY ?? 0, hasBubble ? bubbleFrame.maxY : 0)
    }

    var retryFooterAnchorFrame: NSRect {
        if hasBubble {
            return bubbleFrame
        }
        return imageStripFrame ?? .zero
    }
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
        let imageAttachments: [LocalImageAttachment]
        let bubbleMaxWidth: CGFloat
        let typography: AppKitMarkdownTypography
        let markdownBaseURL: URL?
        let showsRetry: Bool
        let initiallyExpanded: Bool

        init(
            id: String? = nil,
            role: Role,
            markdown: String,
            imageAttachments: [LocalImageAttachment] = [],
            bubbleMaxWidth: CGFloat = .infinity,
            typography: AppKitMarkdownTypography = .default,
            markdownBaseURL: URL? = nil,
            showsRetry: Bool = false,
            initiallyExpanded: Bool = false
        ) {
            self.id = id
            self.role = role
            self.markdown = markdown
            self.imageAttachments = imageAttachments
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
    var onUserInitiatedHeightChange: (() -> Void)?
    var onExpansionChanged: ((Bool) -> Void)?
    var onRetry: (() -> Void)?
    var onOpenMarkdownLink: ((URL) -> Void)? {
        didSet {
            markdownView?.onOpenLink = onOpenMarkdownLink
        }
    }
    var onOpenMarkdownImage: ((BlockInputImage, URL?) -> Void)? {
        didSet {
            markdownView?.onOpenImage = onOpenMarkdownImage
        }
    }
    var onOpenImageAttachment: ((LocalImageAttachment) -> Void)? {
        didSet {
            imageAttachmentStripView.onOpenAttachment = onOpenImageAttachment
        }
    }
    var hydratesMarkdownImmediately = true

    private(set) var bubbleView = AppKitFlippedDynamicColorView()
    private(set) var markdownClipView = AppKitFlippedDynamicColorView()
    private(set) var imageAttachmentStripView = AppKitTranscriptImageAttachmentStripView()
    private(set) var collapsedFadeMask = CAGradientLayer()
    private(set) var expansionButton = AppKitTranscriptHeaderToggleButton()
    private(set) var retryStatusField = NSTextField(labelWithString: "Not sent")
    private(set) var retryButton = NSButton(title: "Retry", target: nil, action: nil)
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
        imageAttachmentStripView.onOpenAttachment = onOpenImageAttachment
        imageAttachmentStripView.configure(configuration.imageAttachments)
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
        addSubview(imageAttachmentStripView)

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
        layoutRetryFooter(anchorFrame: metrics.retryFooterAnchorFrame, configuration: configuration)
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

    func isOverflowing(markdownHeight: CGFloat) -> Bool {
        // AppKit has an exact rendered height here; the SwiftUI raw-markdown
        // heuristic can falsely collapse short lists with several source lines.
        markdownHeight > collapsedMaxHeight + 1
    }

    private func layoutRetryFooter(anchorFrame: NSRect, configuration: Configuration) {
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
        let footerY = anchorFrame.maxY + topSpacing
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
        let contentHeight: CGFloat
        if let lastLayoutMetrics {
            contentHeight = lastLayoutMetrics.contentHeight
        } else if let configuration {
            contentHeight = estimatedContentHeight(for: configuration)
        } else if bubbleView.frame.height > 0 {
            contentHeight = bubbleView.frame.height
        } else {
            contentHeight = (markdownView?.intrinsicContentSize.height ?? 0) + (chatBubbleVerticalPadding * 2)
        }
        let retryHeight = retryButton.isHidden ? 0 : 6 + max(
            retryStatusField.frame.height,
            retryStatusField.fittingSize.height,
            retryButton.frame.height,
            retryButton.fittingSize.height
        )
        return ceil(contentHeight + retryHeight)
    }

    private func estimatedContentHeight(for configuration: Configuration) -> CGFloat {
        let maxWidth = maxBubbleWidth(for: configuration, availableWidth: max(bounds.width, 0))
        let imageStripHeight = imageAttachmentStripView.measuredSize(constrainedTo: maxWidth).height
        let bubbleHeight: CGFloat
        if configuration.hasBubbleContent {
            if bubbleView.frame.height > 0 {
                bubbleHeight = bubbleView.frame.height
            } else {
                bubbleHeight = (markdownView?.intrinsicContentSize.height ?? 0) + (chatBubbleVerticalPadding * 2)
            }
        } else {
            bubbleHeight = 0
        }
        let stripBubbleSpacing = imageStripHeight > 0 && bubbleHeight > 0 ? textBubbleImageStripBubbleSpacing : 0
        return imageStripHeight + stripBubbleSpacing + bubbleHeight
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
        guard lastLayoutMetrics?.overflows ?? true else {
            return
        }
        onUserInitiatedHeightChange?()
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

extension AppKitTranscriptTextBubbleRowView.Configuration {
    var hasBubbleContent: Bool {
        !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func hasSameRenderedContent(as other: Self) -> Bool {
        let sameMaxWidth = bubbleMaxWidth == other.bubbleMaxWidth || abs(bubbleMaxWidth - other.bubbleMaxWidth) <= 0.5
        return id == other.id && role == other.role && markdown == other.markdown && imageAttachments == other.imageAttachments &&
            sameMaxWidth && typography == other.typography && markdownBaseURL == other.markdownBaseURL &&
            showsRetry == other.showsRetry
    }
}

struct AsyncPreparedMarkdown {
    let key: AppKitMarkdownPreparedLayoutKey
    let document: AppMarkdownDocument
}
