@preconcurrency import AppKit
import UniformTypeIdentifiers

@MainActor
protocol AppKitTranscriptAppIconResolving: AnyObject {
    func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage
}

@MainActor
final class AppKitTranscriptWorkspaceAppIconResolver: AppKitTranscriptAppIconResolving {
    static let shared = AppKitTranscriptWorkspaceAppIconResolver()

    private var iconCache: [String: NSImage] = [:]

    func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage {
        let cacheKey = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = iconCache[cacheKey] {
            return cached
        }
        let icon: NSImage
        if !cacheKey.isEmpty,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: cacheKey) {
            icon = NSWorkspace.shared.icon(forFile: appURL.path)
        } else {
            icon = NSWorkspace.shared.icon(for: .application)
        }
        iconCache[cacheKey] = icon
        return icon
    }
}

@MainActor
final class AppKitTranscriptAppShotCardView: AppKitDynamicColorView {
    private static let cornerRadius: CGFloat = 8
    private static let gradientClearanceAboveIcon: CGFloat = 12
    private static let iconSize = NSSize(width: 20, height: 20)
    private static let overlayHorizontalPadding: CGFloat = 12
    private static let overlayBottomPadding: CGFloat = 8
    private static let iconTitleSpacing: CGFloat = 3

    let imageView = AppKitTranscriptAspectFillImageView()
    let iconImageView = NSImageView()
    private let gradientView = NSView()
    private let gradientLayer = CAGradientLayer()
    private let titleField = NSTextField(labelWithString: "")
    private var appShot: PersistedAppShotAttachment?
    var appIconResolver: AppKitTranscriptAppIconResolving = AppKitTranscriptWorkspaceAppIconResolver.shared {
        didSet {
            updateResolvedIcon()
        }
    }
    var onOpenAttachment: ((PersistedAppShotAttachment) -> Void)? {
        didSet {
            updateOpenState()
        }
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateThemeColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateThemeColors()
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds

        let titleHeight = ceil(titleField.intrinsicContentSize.height)
        let titleWidth = max(bounds.width - (Self.overlayHorizontalPadding * 2), 0)
        let titleY = max(bounds.height - Self.overlayBottomPadding - titleHeight, 0)
        let iconY = max(titleY - Self.iconTitleSpacing - Self.iconSize.height, 0)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let gradientY = max(iconY - Self.gradientClearanceAboveIcon, 0)
        gradientView.frame = NSRect(
            x: 0,
            y: gradientY,
            width: bounds.width,
            height: bounds.height - gradientY
        )
        gradientLayer.frame = gradientView.bounds
        CATransaction.commit()

        iconImageView.frame = NSRect(
            x: bounds.midX - (Self.iconSize.width / 2),
            y: iconY,
            width: Self.iconSize.width,
            height: Self.iconSize.height
        )
        titleField.frame = NSRect(
            x: bounds.midX - (titleWidth / 2),
            y: titleY,
            width: titleWidth,
            height: titleHeight
        )
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)),
              performOpen() else {
            super.mouseUp(with: event)
            return
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if onOpenAttachment != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        performOpen()
    }

    func configure(_ appShot: PersistedAppShotAttachment) {
        self.appShot = appShot
        imageView.image = NSImage(contentsOf: appShot.screenshot.fileURL)
        updateResolvedIcon()
        titleField.stringValue = appShot.displayTitle
        toolTip = appShot.displayTitle
        setAccessibilityLabel(accessibilityLabel(for: appShot))
        needsLayout = true
    }

    @discardableResult
    private func performOpen() -> Bool {
        guard let appShot,
              let onOpenAttachment else {
            return false
        }
        onOpenAttachment(appShot)
        return true
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.borderWidth = BlockInputComposerStyle.imagePreviewBorderWidth
        layer?.masksToBounds = true
        setLayerFillColor(transcriptImageAttachmentFillColor)
        setLayerStrokeColorPreservingResolvedAlpha { _ in
            transcriptImageAttachmentBorderColor
        }

        imageView.cornerRadius = Self.cornerRadius
        addSubview(imageView)

        gradientView.wantsLayer = true
        gradientView.layer?.masksToBounds = true
        addSubview(gradientView)

        gradientLayer.locations = [0, 0.55, 1]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        gradientView.layer?.addSublayer(gradientLayer)

        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.wantsLayer = true
        iconImageView.layer?.cornerRadius = 4
        iconImageView.layer?.masksToBounds = true
        addSubview(iconImageView)

        titleField.font = TranscriptTypography().nsFont(.caption, weight: .medium)
        titleField.alignment = .center
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.cell?.truncatesLastVisibleLine = true
        titleField.backgroundColor = .clear
        titleField.isBordered = false
        titleField.isEditable = false
        titleField.isSelectable = false
        addSubview(titleField)

        setAccessibilityElement(true)
        updateThemeColors()
        updateOpenState()
    }

    private func updateThemeColors() {
        let appearance = appKitRenderingAppearance
        let fadeColor = NSColor.windowBackgroundColor.resolved(for: appearance)
        gradientLayer.colors = [
            fadeColor.withAlphaComponent(0.98).cgColor,
            fadeColor.withAlphaComponent(0.68).cgColor,
            fadeColor.withAlphaComponent(0).cgColor
        ]
        titleField.textColor = NSColor.labelColor.resolved(for: appearance)
    }

    private func updateOpenState() {
        setAccessibilityRole(onOpenAttachment == nil ? .image : .button)
        window?.invalidateCursorRects(for: self)
    }

    private func updateResolvedIcon() {
        guard let appShot else {
            return
        }
        iconImageView.image = appIconResolver.icon(forBundleIdentifier: appShot.bundleIdentifier)
    }

    private func accessibilityLabel(for appShot: PersistedAppShotAttachment) -> String {
        let appName = appShot.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = appShot.displayTitle
        if appName.isEmpty || appName == title {
            return "App shot, \(title)"
        }
        return "App shot, \(appName), \(title)"
    }
}

#if DEBUG
extension AppKitTranscriptAppShotCardView {
    var imageViewFrameForTesting: CGRect {
        imageView.frame
    }

    var imageFrameForTesting: CGRect? {
        imageView.aspectFillImageFrameForTesting
    }

    var iconImageForTesting: NSImage? {
        iconImageView.image
    }

    var iconFrameForTesting: CGRect {
        iconImageView.frame
    }

    var titleFrameForTesting: CGRect {
        titleField.frame
    }
}
#endif
