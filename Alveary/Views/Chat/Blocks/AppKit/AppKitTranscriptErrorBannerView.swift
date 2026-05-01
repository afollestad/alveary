@preconcurrency import AppKit
import Foundation

@MainActor
final class AppKitTranscriptErrorBannerView: NSView {
    struct Configuration: Equatable {
        let message: String
        let bubbleMaxWidth: CGFloat
        let typography: TranscriptTypography

        init(
            message: String,
            bubbleMaxWidth: CGFloat = .infinity,
            typography: TranscriptTypography = TranscriptTypography()
        ) {
            self.message = message
            self.bubbleMaxWidth = bubbleMaxWidth
            self.typography = typography
        }
    }

    var onHeightInvalidated: (() -> Void)?

    private let bannerView = AppKitFlippedDynamicColorView()
    private let iconView = AppKitDynamicTintImageView()
    private let messageField = NSTextField(labelWithString: "")
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
        messageField.stringValue = configuration.message
        messageField.font = configuration.typography.nsFont(.subheadline)
        messageField.setAccessibilityLabel(configuration.message)
        needsLayout = true
        updateAppearance()
        invalidateTranscriptHeight(force: true)
    }

    override func layout() {
        layoutContent()
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        bannerView.wantsLayer = true
        bannerView.layer?.cornerRadius = errorBannerCornerRadius
        addSubview(bannerView)

        iconView.translatesAutoresizingMaskIntoConstraints = true
        iconView.image = NSImage(systemSymbolName: "xmark.octagon.fill", accessibilityDescription: nil)
        iconView.setAccessibilityElement(false)
        bannerView.addSubview(iconView)

        messageField.translatesAutoresizingMaskIntoConstraints = true
        messageField.lineBreakMode = .byWordWrapping
        messageField.maximumNumberOfLines = 0
        bannerView.addSubview(messageField)
        updateAppearance()
    }

    private func layoutContent() {
        guard let configuration, bounds.width > 0 else {
            return
        }

        let width = bannerWidth(for: configuration)
        bannerView.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude / 2)
        iconView.frame = NSRect(
            x: errorBannerHorizontalPadding,
            y: errorBannerVerticalPadding,
            width: errorBannerIconSize,
            height: errorBannerIconSize
        )

        let messageX = iconView.frame.maxX + errorBannerIconTextSpacing
        let messageWidth = max(width - messageX - errorBannerHorizontalPadding, 0)
        messageField.frame = NSRect(
            x: messageX,
            y: errorBannerVerticalPadding,
            width: messageWidth,
            height: textHeight(for: messageWidth)
        )
        let contentHeight = max(errorBannerIconSize, messageField.frame.height)
        iconView.frame.origin.y = errorBannerVerticalPadding + max((contentHeight - errorBannerIconSize) / 2, 0)
        bannerView.frame.size.height = ceil((errorBannerVerticalPadding * 2) + contentHeight)
    }

    private func bannerWidth(for configuration: Configuration) -> CGFloat {
        let availableWidth = max(bounds.width, 0)
        let cap = configuration.bubbleMaxWidth.isFinite ? configuration.bubbleMaxWidth : availableWidth
        return min(max(cap, 0), availableWidth)
    }

    private func updateAppearance() {
        let red = NSColor.systemRed
        bannerView.setLayerFillColor(red, alpha: 0.12)
        bannerView.setLayerStrokeColor(red, alpha: 0.3)
        bannerView.layer?.borderWidth = 1
        iconView.setDynamicContentTintColor(red)
        messageField.textColor = .labelColor
    }

    private func measuredHeight() -> CGFloat {
        if bannerView.frame.height > 0, bannerView.frame.height < CGFloat.greatestFiniteMagnitude / 4 {
            return ceil(bannerView.frame.height)
        }
        return ceil((errorBannerVerticalPadding * 2) + max(errorBannerIconSize, messageField.fittingSize.height))
    }

    private func textHeight(for width: CGFloat) -> CGFloat {
        guard width > 0 else {
            return messageField.fittingSize.height
        }
        let rect = messageField.attributedStringValue.boundingRect(
            with: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude / 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.height)
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
}

private let errorBannerCornerRadius: CGFloat = 14
private let errorBannerHorizontalPadding: CGFloat = 14
private let errorBannerVerticalPadding: CGFloat = 10
private let errorBannerIconSize: CGFloat = 16
private let errorBannerIconTextSpacing: CGFloat = 12
