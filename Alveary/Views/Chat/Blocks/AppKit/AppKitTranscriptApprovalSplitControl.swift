@preconcurrency import AppKit

final class AppKitTranscriptApprovalSplitControl: NSSegmentedControl {
    static let menuWidth: CGFloat = 22

    /// Leading glyph on the primary half. Defaults to the approval checkmark so
    /// approval rows keep their exact appearance.
    var primarySymbolName = "checkmark" {
        didSet { needsDisplay = true }
    }
    var actionStyle: AppKitTranscriptApprovalButtonStyle = .primary {
        didSet { needsDisplay = true }
    }

    var preferredContentWidth: CGFloat {
        let titleWidth = ceil(((label(forSegment: 0) ?? "") as NSString).size(withAttributes: [.font: drawingFont]).width)
        return ceil(
            (AppKitTranscriptApprovalButtonMetrics.horizontalPadding * 2)
                + AppKitTranscriptApprovalButtonMetrics.iconSize
                + AppKitTranscriptApprovalButtonMetrics.iconTextSpacing
                + titleWidth
        )
    }

    var preferredWidth: CGFloat {
        preferredContentWidth + Self.menuWidth
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

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: bounds,
            xRadius: AppKitTranscriptApprovalButtonMetrics.cornerRadius,
            yRadius: AppKitTranscriptApprovalButtonMetrics.cornerRadius
        )
        fillColor.setFill()
        path.fill()
        if isHovering, isEnabled {
            NSColor.labelColor.appKitResolvedColor(in: self, alpha: 0.06).setFill()
            path.fill()
        }
        if actionStyle == .secondary {
            NSColor.labelColor.appKitResolvedColor(in: self, alpha: isEnabled ? 0.12 : 0.06).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        let dividerX = bounds.maxX - Self.menuWidth
        NSColor.labelColor.appKitResolvedColor(in: self, alpha: isEnabled ? 0.16 : 0.08).setFill()
        NSRect(x: dividerX, y: 4, width: 1, height: bounds.height - 8).fill()

        drawMainLabel(in: NSRect(x: 0, y: 0, width: dividerX, height: bounds.height))
        drawChevron(in: NSRect(x: dividerX, y: 0, width: Self.menuWidth, height: bounds.height))
    }

    private var drawingFont: NSFont {
        .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    }

    private var foregroundColor: NSColor {
        .labelColor.appKitResolvedColor(in: self, alpha: isEnabled ? 1 : 0.78)
    }

    private var fillColor: NSColor {
        switch actionStyle {
        case .primary:
            return AppAccentFill.primaryNSColor.appKitResolvedColor(in: self, alpha: isEnabled ? 1 : 0.38)
        case .secondary:
            return NSColor.labelColor.appKitResolvedColor(in: self, alpha: isEnabled ? 0.12 : 0.06)
        }
    }

    private func drawMainLabel(in rect: NSRect) {
        let title = label(forSegment: 0) ?? ""
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: drawingFont,
            .foregroundColor: foregroundColor
        ]
        let titleSize = (title as NSString).size(withAttributes: textAttributes)
        let contentWidth = AppKitTranscriptApprovalButtonMetrics.iconSize
            + AppKitTranscriptApprovalButtonMetrics.iconTextSpacing
            + titleSize.width
        var currentX = floor(rect.midX - (contentWidth / 2))
        let centerY = rect.midY

        drawSymbol(primarySymbolName, in: NSRect(
            x: currentX,
            y: floor(centerY - (AppKitTranscriptApprovalButtonMetrics.iconSize / 2)),
            width: AppKitTranscriptApprovalButtonMetrics.iconSize,
            height: AppKitTranscriptApprovalButtonMetrics.iconSize
        ))
        currentX += AppKitTranscriptApprovalButtonMetrics.iconSize + AppKitTranscriptApprovalButtonMetrics.iconTextSpacing

        let titleRect = NSRect(
            x: currentX,
            y: floor(centerY - (titleSize.height / 2)),
            width: titleSize.width,
            height: titleSize.height
        )
        (title as NSString).draw(in: titleRect, withAttributes: textAttributes)
    }

    private func drawChevron(in rect: NSRect) {
        drawSymbol("chevron.down", in: NSRect(
            x: floor(rect.midX - 5),
            y: floor(rect.midY - 5),
            width: 10,
            height: 10
        ))
    }

    private func drawSymbol(_ name: String, in rect: NSRect) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            .applying(.init(hierarchicalColor: foregroundColor))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else {
            return
        }
        image.draw(in: symbolDrawingRect(for: image, in: rect), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func symbolDrawingRect(for image: NSImage, in rect: NSRect) -> NSRect {
        let size = image.size
        guard size.width > 0, size.height > 0, rect.width > 0, rect.height > 0 else {
            return rect
        }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let drawingSize = NSSize(width: ceil(size.width * scale), height: ceil(size.height * scale))
        return NSRect(
            x: floor(rect.midX - (drawingSize.width / 2)),
            y: floor(rect.midY - (drawingSize.height / 2)),
            width: drawingSize.width,
            height: drawingSize.height
        )
    }
}

#if DEBUG
extension AppKitTranscriptApprovalSplitControl {
    func setHoveringForTesting(_ isHovering: Bool) {
        self.isHovering = isHovering
        needsDisplay = true
    }

    func symbolDrawingRectForTesting(symbolName: String, in rect: NSRect) -> NSRect? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            .applying(.init(hierarchicalColor: foregroundColor))
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else {
            return nil
        }
        return symbolDrawingRect(for: image, in: rect)
    }
}
#endif
