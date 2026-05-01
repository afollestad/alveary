import AppKit

/// Native circular icon-only button matching `iconActionButtonStyle` geometry,
/// tint, and hover/pressed treatment for composer action-row accessories.
final class ComposerIconButton: NSView {
    var actionHandler: (() -> Void)?

    private let symbolName: String
    private var isPressed = false
    private var isHovering = false
    private var trackingArea: NSTrackingArea?

    init(symbolName: String) {
        self.symbolName = symbolName
        super.init(frame: .zero)
        setContentHuggingPriority(.required, for: .horizontal)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) {
        symbolName = "circle"
        super.init(coder: coder)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 30, height: 30)
    }

    override var isHidden: Bool {
        didSet {
            if isHidden {
                resetInteractionState()
            }
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil {
            resetInteractionState()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            resetInteractionState()
        }
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        resetInteractionState()
    }

    override func mouseDown(with event: NSEvent) {
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
        actionHandler?()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isHovering {
            NSColor.secondaryLabelColor.appKitResolvedColor(in: self, alpha: 0.16).setFill()
            NSBezierPath(ovalIn: bounds).fill()
        }

        guard let image = symbolImage(
            named: symbolName,
            color: NSColor.labelColor.appKitResolvedColor(in: self, alpha: isHovering ? 0.95 : 0.80)
        ) else {
            return
        }
        let imageSize = image.size
        image.draw(
            in: NSRect(
                x: floor((bounds.width - imageSize.width) / 2),
                y: floor((bounds.height - imageSize.height) / 2),
                width: imageSize.width,
                height: imageSize.height
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
    }

    private func symbolImage(named name: String, color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
            .applying(.init(hierarchicalColor: color))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    private func resetInteractionState() {
        isPressed = false
        isHovering = false
        needsDisplay = true
    }
}
