import AppKit

/// Small native button used by composer top-content banners.
///
/// It mirrors the low-emphasis SwiftUI banner buttons without introducing an
/// `NSButton` bezel that would diverge from the composer action-row styling.
@MainActor
final class ComposerTopContentButton: NSView {
    enum Style {
        case secondary
        case icon(symbolName: String)
    }

    var actionHandler: (() -> Void)?

    private let style: Style
    private var title = ""
    private var controlIsEnabled = true
    private var isHovering = false
    private var isPressed = false
    private var trackingArea: NSTrackingArea?

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        switch style {
        case .secondary:
            let width = ceil(title.size(withAttributes: [.font: Self.titleFont]).width) + 18
            return NSSize(width: max(48, width), height: 22)
        case .icon:
            return NSSize(width: 22, height: 22)
        }
    }

    override var isHidden: Bool {
        didSet {
            if isHidden {
                resetInteractionState()
            }
        }
    }

    func configure(title: String, isEnabled: Bool) {
        self.title = title
        controlIsEnabled = isEnabled
        setAccessibilityLabel(title)
        setAccessibilityEnabled(isEnabled)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            resetInteractionState()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard controlIsEnabled else {
            return
        }
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        resetInteractionState()
    }

    override func mouseDown(with event: NSEvent) {
        guard controlIsEnabled else {
            return
        }
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isPressed else {
            return
        }
        isPressed = false
        needsDisplay = true
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            actionHandler?()
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard controlIsEnabled else {
            return false
        }
        actionHandler?()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        switch style {
        case .secondary:
            drawSecondaryButton()
        case .icon(let symbolName):
            drawIconButton(symbolName: symbolName)
        }
    }

    private func drawSecondaryButton() {
        let fillAlpha: CGFloat = isPressed ? 0.16 : (isHovering ? 0.12 : 0.08)
        NSColor.labelColor.appKitResolvedColor(in: self, alpha: fillAlpha).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: AppCornerRadius.standard, yRadius: AppCornerRadius.standard).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.titleFont,
            .foregroundColor: NSColor.labelColor.appKitResolvedColor(in: self, alpha: controlIsEnabled ? 0.85 : 0.26)
        ]
        let size = title.size(withAttributes: attributes)
        (title as NSString).draw(
            at: NSPoint(x: floor((bounds.width - size.width) / 2), y: floor((bounds.height - size.height) / 2)),
            withAttributes: attributes
        )
    }

    private func drawIconButton(symbolName: String) {
        if isHovering {
            NSColor.secondaryLabelColor.appKitResolvedColor(in: self, alpha: 0.16).setFill()
            NSBezierPath(ovalIn: bounds).fill()
        }
        guard let image = symbolImage(
            named: symbolName,
            color: NSColor.secondaryLabelColor.appKitResolvedColor(in: self, alpha: isHovering ? 0.95 : 0.80)
        ) else {
            return
        }
        let imageRect = NSRect(
            x: floor((bounds.width - image.size.width) / 2),
            y: floor((bounds.height - image.size.height) / 2),
            width: image.size.width,
            height: image.size.height
        )
        image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func symbolImage(named name: String, color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(.init(hierarchicalColor: color))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    private func resetInteractionState() {
        isHovering = false
        isPressed = false
        needsDisplay = true
    }

    private static let titleFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
}
