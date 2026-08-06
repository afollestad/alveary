@preconcurrency import AppKit

enum AppKitTranscriptApprovalButtonMetrics {
    static let height: CGFloat = 24
    static let horizontalPadding: CGFloat = 10
    static let iconSize: CGFloat = 14
    static let iconTextSpacing: CGFloat = 6
    static let shortcutHorizontalPadding: CGFloat = 7
    static let shortcutHeight: CGFloat = 18
    static let shortcutSymbolSize: CGFloat = 12
    static let shortcutSpacing: CGFloat = 7
    static let cornerRadius: CGFloat = AppCornerRadius.standard
}

enum AppKitTranscriptApprovalButtonStyle {
    case primary
    case secondary
}

final class AppKitTranscriptApprovalButton: NSButton {
    var actionStyle: AppKitTranscriptApprovalButtonStyle = .primary {
        didSet { needsDisplay = true }
    }
    /// `draw(_:)` paints this itself, so `NSButton.image` is cleared and its
    /// positioning/scaling properties are inert.
    var icon: ActionIcon? {
        didSet {
            image = nil
            needsDisplay = true
            invalidateIntrinsicContentSize()
        }
    }
    var shortcutTitle: String? {
        didSet {
            needsDisplay = true
            invalidateIntrinsicContentSize()
        }
    }
    var keyEventHandler: ((NSEvent) -> Bool)?

    var preferredWidth: CGFloat {
        let titleWidth = ceil((title as NSString).size(withAttributes: [.font: drawingFont]).width)
        let imageWidth = icon == nil ? 0 :
            AppKitTranscriptApprovalButtonMetrics.iconSize + AppKitTranscriptApprovalButtonMetrics.iconTextSpacing
        let shortcutWidth = measuredShortcutWidth
        let shortcutSpacing = shortcutWidth > 0 ? AppKitTranscriptApprovalButtonMetrics.shortcutSpacing : 0
        return ceil((AppKitTranscriptApprovalButtonMetrics.horizontalPadding * 2) + imageWidth + titleWidth)
            + shortcutSpacing
            + shortcutWidth
    }

    override var fittingSize: NSSize {
        NSSize(width: preferredWidth, height: AppKitTranscriptApprovalButtonMetrics.height)
    }

    override var intrinsicContentSize: NSSize {
        fittingSize
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private var isHovering = false
    private var isPressed = false
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = newTrackingArea
        addTrackingArea(newTrackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            return
        }
        isPressed = true
        needsDisplay = true
        super.mouseDown(with: event)
        isPressed = false
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if keyEventHandler?(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawBackground()
        drawContents()
    }

    private var drawingFont: NSFont {
        font ?? .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    }

    private var foregroundColor: NSColor {
        .labelColor.appKitResolvedColor(in: self, alpha: isEnabled ? 1 : 0.78)
    }

    private var fillColor: NSColor {
        switch actionStyle {
        case .primary:
            let alpha: CGFloat = isEnabled ? (isPressed ? 0.84 : 1) : 0.38
            return AppAccentFill.primaryNSColor.appKitResolvedColor(in: self, alpha: alpha)
        case .secondary:
            return NSColor.labelColor.appKitResolvedColor(in: self, alpha: isEnabled ? 0.12 : 0.06)
        }
    }

    private func drawBackground() {
        let path = NSBezierPath(
            roundedRect: bounds,
            xRadius: AppKitTranscriptApprovalButtonMetrics.cornerRadius,
            yRadius: AppKitTranscriptApprovalButtonMetrics.cornerRadius
        )
        fillColor.setFill()
        path.fill()
        if isHovering, isEnabled, !isPressed {
            NSColor.labelColor.appKitResolvedColor(in: self, alpha: 0.06).setFill()
            path.fill()
        }
        if actionStyle == .secondary {
            NSColor.labelColor.appKitResolvedColor(in: self, alpha: isEnabled ? 0.12 : 0.06).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawContents() {
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: drawingFont,
            .foregroundColor: foregroundColor
        ]
        let titleSize = (title as NSString).size(withAttributes: textAttributes)
        let imageWidth = icon == nil ? 0 :
            AppKitTranscriptApprovalButtonMetrics.iconSize + AppKitTranscriptApprovalButtonMetrics.iconTextSpacing
        let shortcutWidth = measuredShortcutWidth
        let shortcutSpacing = shortcutWidth > 0 ? AppKitTranscriptApprovalButtonMetrics.shortcutSpacing : 0
        let contentWidth = imageWidth + titleSize.width + shortcutSpacing + shortcutWidth
        var currentX = floor((bounds.width - contentWidth) / 2)
        let centerY = bounds.midY

        if let icon,
           let image = iconImage(icon, color: foregroundColor) {
            let imageRect = NSRect(
                x: currentX,
                y: floor(centerY - (AppKitTranscriptApprovalButtonMetrics.iconSize / 2)),
                width: AppKitTranscriptApprovalButtonMetrics.iconSize,
                height: AppKitTranscriptApprovalButtonMetrics.iconSize
            )
            image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            currentX += imageWidth
        }

        let titleRect = NSRect(
            x: currentX,
            y: floor(centerY - (titleSize.height / 2)),
            width: titleSize.width,
            height: titleSize.height
        )
        (title as NSString).draw(in: titleRect, withAttributes: textAttributes)
        currentX = titleRect.maxX + shortcutSpacing

        if let shortcutTitle, !shortcutTitle.isEmpty {
            drawShortcut(title: shortcutTitle, originX: currentX, centerY: centerY)
        }
    }

    private var measuredShortcutWidth: CGFloat {
        guard let shortcutTitle, !shortcutTitle.isEmpty else {
            return 0
        }
        if shortcutSymbolName(for: shortcutTitle) != nil {
            return ceil(AppKitTranscriptApprovalButtonMetrics.shortcutSymbolSize +
                (AppKitTranscriptApprovalButtonMetrics.shortcutHorizontalPadding * 2))
        }
        let width = (shortcutTitle as NSString).size(withAttributes: [.font: shortcutFont]).width
        return ceil(width + (AppKitTranscriptApprovalButtonMetrics.shortcutHorizontalPadding * 2))
    }

    private var shortcutFont: NSFont {
        .systemFont(ofSize: 12, weight: .medium)
    }

    private func drawShortcut(title: String, originX: CGFloat, centerY: CGFloat) {
        let rect = shortcutBackgroundRect(originX: originX, centerY: centerY)
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: AppKitTranscriptApprovalButtonMetrics.shortcutHeight / 2,
            yRadius: AppKitTranscriptApprovalButtonMetrics.shortcutHeight / 2
        )
        NSColor.labelColor.appKitResolvedColor(in: self, alpha: actionStyle == .primary ? 0.16 : 0.12).setFill()
        path.fill()

        if let image = shortcutSymbolImage(for: title) {
            image.draw(
                in: centeredImageRect(for: image, in: rect),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: shortcutFont,
            .foregroundColor: foregroundColor
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        let textRect = NSRect(
            x: rect.midX - (size.width / 2),
            y: floor(rect.midY - (size.height / 2)),
            width: size.width,
            height: size.height
        )
        (title as NSString).draw(in: textRect, withAttributes: attributes)
    }

    private func shortcutBackgroundRect(originX: CGFloat, centerY: CGFloat) -> NSRect {
        NSRect(
            x: originX,
            y: floor(centerY - (AppKitTranscriptApprovalButtonMetrics.shortcutHeight / 2)),
            width: measuredShortcutWidth,
            height: AppKitTranscriptApprovalButtonMetrics.shortcutHeight
        )
    }

    private func shortcutSymbolImage(for title: String) -> NSImage? {
        guard let symbolName = shortcutSymbolName(for: title) else {
            return nil
        }
        let configuration = NSImage.SymbolConfiguration(
            pointSize: AppKitTranscriptApprovalButtonMetrics.shortcutSymbolSize,
            weight: .semibold
        )
        .applying(.init(hierarchicalColor: foregroundColor))
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    private func shortcutSymbolName(for title: String) -> String? {
        title == "↩" ? "return" : nil
    }

    private func centeredImageRect(for image: NSImage, in rect: NSRect) -> NSRect {
        let size = image.size
        guard size.width > 0, size.height > 0, rect.width > 0, rect.height > 0 else {
            return rect
        }
        let maxSymbolSize = AppKitTranscriptApprovalButtonMetrics.shortcutSymbolSize
        let scale = min(maxSymbolSize / size.width, maxSymbolSize / size.height)
        let drawingSize = NSSize(width: ceil(size.width * scale), height: ceil(size.height * scale))
        return NSRect(
            x: floor(rect.midX - (drawingSize.width / 2)),
            y: floor(rect.midY - (drawingSize.height / 2)),
            width: drawingSize.width,
            height: drawingSize.height
        )
    }

    /// Both sources resolve to the title's colour, so the glyph dims with the
    /// label rather than staying at full strength when the button disables.
    private func iconImage(_ icon: ActionIcon, color: NSColor) -> NSImage? {
        icon.nsImage(side: AppKitTranscriptApprovalButtonMetrics.iconSize, color: color)
    }
}

#if DEBUG
extension AppKitTranscriptApprovalButton {
    var iconForTesting: ActionIcon? {
        icon
    }

    func shortcutSymbolDrawingRectForTesting(title: String, in rect: NSRect) -> NSRect? {
        guard let image = shortcutSymbolImage(for: title) else {
            return nil
        }
        return centeredImageRect(for: image, in: rect)
    }

    func setInteractionStateForTesting(isHovering: Bool = false, isPressed: Bool = false) {
        self.isHovering = isHovering
        self.isPressed = isPressed
        needsDisplay = true
    }
}
#endif
