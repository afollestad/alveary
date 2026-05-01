@preconcurrency import AppKit

/// Primary prompt action button that mirrors SwiftUI's regular `primaryActionButtonStyle` metrics.
final class AppKitPromptSubmitButton: NSButton {
    private enum Metrics {
        static let height: CGFloat = 30
        static let horizontalPadding: CGFloat = 12
        static let cornerRadius: CGFloat = 10
    }

    private var isHovering = false
    private var isPressed = false
    private var trackingArea: NSTrackingArea?

    override var fittingSize: NSSize {
        let titleWidth = ceil((title as NSString).size(withAttributes: [.font: drawingFont]).width)
        return NSSize(width: titleWidth + (Metrics.horizontalPadding * 2), height: Metrics.height)
    }

    override var intrinsicContentSize: NSSize {
        fittingSize
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

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

    override func draw(_ dirtyRect: NSRect) {
        drawBackground()
        drawTitle()
    }

    private var drawingFont: NSFont {
        font ?? .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    }

    private var foregroundColor: NSColor {
        .labelColor.appKitResolvedColor(in: self, alpha: isEnabled ? 1 : 0.78)
    }

    private var fillColor: NSColor {
        let alpha: CGFloat = isEnabled ? (isPressed ? 0.84 : 1) : 0.38
        return AppAccentFill.primaryNSColor.appKitResolvedColor(in: self, alpha: alpha)
    }

    private func drawBackground() {
        let path = NSBezierPath(
            roundedRect: bounds,
            xRadius: Metrics.cornerRadius,
            yRadius: Metrics.cornerRadius
        )
        fillColor.setFill()
        path.fill()
        if isHovering, isEnabled, !isPressed {
            foregroundColor.withAlphaComponent(0.06).setFill()
            path.fill()
        }
    }

    private func drawTitle() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: drawingFont,
            .foregroundColor: foregroundColor
        ]
        let titleSize = (title as NSString).size(withAttributes: attributes)
        let titleRect = NSRect(
            x: floor((bounds.width - titleSize.width) / 2),
            y: floor((bounds.height - titleSize.height) / 2),
            width: titleSize.width,
            height: titleSize.height
        )
        (title as NSString).draw(in: titleRect, withAttributes: attributes)
    }
}
