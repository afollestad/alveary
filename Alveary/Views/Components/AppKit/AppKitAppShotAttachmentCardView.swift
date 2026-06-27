@preconcurrency import AppKit
import UniformTypeIdentifiers

/// Resolves app icons for app-shot attachment previews.
@MainActor
protocol AppKitAppIconResolving: AnyObject {
    /// Returns an icon for a bundle identifier, or a generic app icon when the bundle cannot be resolved.
    func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage
}

/// `NSWorkspace`-backed app icon resolver shared by transcript and composer app-shot previews.
@MainActor
final class AppKitWorkspaceAppIconResolver: AppKitAppIconResolving {
    static let shared = AppKitWorkspaceAppIconResolver()

    private var iconCache: [String: NSImage] = [:]

    /// Returns the installed app icon for a bundle identifier, caching repeated lookups.
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

/// Preview card for an app-shot screenshot with the captured app icon and window title overlaid.
///
/// The component is model-agnostic: transcript and composer callers configure
/// the visible app-shot values, then attach open/remove callbacks that route
/// back to their own attachment models.
@MainActor
final class AppKitAppShotAttachmentCardView: AppKitDynamicColorView {
    private static let cornerRadius: CGFloat = 8
    private static let gradientClearanceAboveIcon: CGFloat = 16
    private static let iconSize = NSSize(width: 28, height: 28)
    private static let overlayHorizontalPadding: CGFloat = 14
    private static let overlayBottomPadding: CGFloat = 10
    private static let iconTitleSpacing: CGFloat = 4

    let imageView = AppKitAspectFillImageView()
    let iconImageView = NSImageView()
    private let gradientView = NSView()
    private let gradientLayer = CAGradientLayer()
    private let titleField = NSTextField(labelWithString: "")
    private let removeButton = AppKitAttachmentRemoveButton()
    private var bundleIdentifier = ""
    private var appName = ""
    private var displayTitle = ""

    var appIconResolver: AppKitAppIconResolving = AppKitWorkspaceAppIconResolver.shared {
        didSet {
            updateResolvedIcon()
        }
    }
    var onOpenAttachment: (() -> Void)? {
        didSet {
            updateOpenState()
        }
    }
    var onRemoveAttachment: (() -> Void)? {
        didSet {
            updateRemoveState()
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
        invalidateCursorRectsIfPossible()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldSize = frame.size
        super.setFrameSize(newSize)
        if oldSize != newSize {
            updateRemoveButtonFrame()
            invalidateCursorRectsIfPossible()
        }
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
        updateRemoveButtonFrame()
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if removeButtonConsumesClick(at: point) {
            return
        }
        guard bounds.contains(point),
              performOpen() else {
            super.mouseUp(with: event)
            return
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else {
            return nil
        }
        if !removeButton.isHidden,
           removeButtonFrame.contains(point) {
            updateRemoveButtonFrame()
            let removePoint = convert(point, to: removeButton)
            if let hit = removeButton.hitTest(removePoint) {
                return hit
            }
        }
        return self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if !removeButton.isHidden {
            addCursorRect(removeButtonFrame, cursor: .pointingHand)
        }
        if onOpenAttachment != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        performOpen()
    }

    /// Updates the card from a persisted transcript app-shot attachment.
    func configure(_ appShot: PersistedAppShotAttachment) {
        configure(
            screenshot: appShot.screenshot,
            appName: appShot.appName,
            bundleIdentifier: appShot.bundleIdentifier,
            displayTitle: appShot.displayTitle
        )
    }

    /// Updates the card from a staged composer app-shot attachment.
    func configure(_ appShot: AppShotAttachment) {
        configure(
            screenshot: appShot.screenshot,
            appName: appShot.appName,
            bundleIdentifier: appShot.bundleIdentifier,
            displayTitle: appShot.displayTitle
        )
    }

    /// Updates the card image, icon, title, tooltip, and accessibility label.
    func configure(
        screenshot: LocalImageAttachment,
        appName: String,
        bundleIdentifier: String,
        displayTitle: String
    ) {
        imageView.image = NSImage(contentsOf: screenshot.fileURL)
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.displayTitle = displayTitle
        updateResolvedIcon()
        titleField.stringValue = displayTitle
        toolTip = displayTitle
        setAccessibilityLabel(accessibilityLabel(appName: appName, displayTitle: displayTitle))
        removeButton.toolTip = "Remove \(displayTitle)"
        needsLayout = true
    }

    @discardableResult
    private func performOpen() -> Bool {
        guard let onOpenAttachment else {
            return false
        }
        onOpenAttachment()
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
        iconImageView.layer?.cornerRadius = 6
        iconImageView.layer?.masksToBounds = true
        addSubview(iconImageView)

        titleField.font = .systemFont(ofSize: 15, weight: .semibold)
        titleField.alignment = .center
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.cell?.truncatesLastVisibleLine = true
        titleField.backgroundColor = .clear
        titleField.isBordered = false
        titleField.isEditable = false
        titleField.isSelectable = false
        addSubview(titleField)

        removeButton.onPress = { [weak self] in
            self?.onRemoveAttachment?()
        }
        addSubview(removeButton)

        setAccessibilityElement(true)
        updateThemeColors()
        updateOpenState()
        updateRemoveState()
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
        invalidateCursorRectsIfPossible()
    }

    private func updateRemoveState() {
        removeButton.isHidden = onRemoveAttachment == nil
        invalidateCursorRectsIfPossible()
    }

    private func removeButtonConsumesClick(at point: NSPoint) -> Bool {
        guard !removeButton.isHidden,
              removeButtonFrame.contains(point) else {
            return false
        }
        return removeButton.performPress()
    }

    private var removeButtonFrame: NSRect {
        NSRect(
            x: max(bounds.maxX - BlockInputComposerStyle.imagePreviewRemoveButtonSize.width - 6, 0),
            y: 6,
            width: BlockInputComposerStyle.imagePreviewRemoveButtonSize.width,
            height: BlockInputComposerStyle.imagePreviewRemoveButtonSize.height
        )
    }

    private func updateRemoveButtonFrame() {
        removeButton.frame = removeButtonFrame
    }

    private func invalidateCursorRectsIfPossible() {
        window?.invalidateCursorRects(for: self)
    }

    private func updateResolvedIcon() {
        iconImageView.image = appIconResolver.icon(forBundleIdentifier: bundleIdentifier)
    }

    private func accessibilityLabel(appName: String, displayTitle: String) -> String {
        let appName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if appName.isEmpty || appName == displayTitle {
            return "App shot, \(displayTitle)"
        }
        return "App shot, \(appName), \(displayTitle)"
    }
}

#if DEBUG
extension AppKitAppShotAttachmentCardView {
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

private extension AppShotAttachment {
    var displayTitle: String {
        let candidates = [windowTitle, appName, "App shot"]
        return candidates.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "App shot"
    }
}
