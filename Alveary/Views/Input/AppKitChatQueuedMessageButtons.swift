import AppKit

@MainActor
final class AppKitChatQueuedMessageSteerButton: NSView {
    var actionHandler: (() -> Void)?

    private var controlIsEnabled = true
    private var isPressed = false
    private var isHovering = false
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 82, height: 30)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupAccessibility()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupAccessibility()
    }

    func configure(isEnabled: Bool) {
        controlIsEnabled = isEnabled
        if !isEnabled {
            resetInteractionState()
        }
        alphaValue = isEnabled ? 1 : 0.45
        setAccessibilityEnabled(isEnabled)
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
        guard isPressed, controlIsEnabled else {
            resetInteractionState()
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
        appKitComposerPrimaryColor(in: self, opacity: isPressed ? 0.16 : (isHovering ? 0.12 : 0.08)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: AppCornerRadius.standard, yRadius: AppCornerRadius.standard).fill()
        drawTitle()
    }

    private func setupAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Steer queued message")
    }

    private func drawTitle() {
        let foreground = NSColor.labelColor.appKitResolvedColor(in: self, alpha: controlIsEnabled ? 0.85 : 0.35)
        let text = "Steer"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
            .foregroundColor: foreground
        ]
        let titleSize = text.size(withAttributes: attributes)
        let imageSize = NSSize(width: 13, height: 13)
        var contentX = floor((bounds.width - imageSize.width - 6 - titleSize.width) / 2)
        if let image = Self.symbolImage(named: "arrow.turn.down.left", color: foreground) {
            image.draw(
                in: NSRect(x: contentX, y: floor((bounds.height - 13) / 2), width: 13, height: 13),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
        }
        contentX += imageSize.width + 6
        (text as NSString).draw(
            in: NSRect(
                x: contentX,
                y: floor((bounds.height - titleSize.height) / 2),
                width: titleSize.width,
                height: titleSize.height
            ),
            withAttributes: attributes
        )
    }

    private static func symbolImage(named name: String, color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            .applying(.init(hierarchicalColor: color))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    private func resetInteractionState() {
        isHovering = false
        isPressed = false
        needsDisplay = true
    }
}

@MainActor
final class AppKitChatQueuedMessageIconButton: NSView {
    var actionHandler: (() -> Void)?

    private let symbolName: String
    private let isDestructive: Bool
    private var controlIsEnabled = true
    private var isPressed = false
    private var isHovering = false
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 30, height: 30)
    }

    init(symbolName: String, isDestructive: Bool) {
        self.symbolName = symbolName
        self.isDestructive = isDestructive
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) {
        symbolName = "circle"
        isDestructive = false
        super.init(coder: coder)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    func configure(isEnabled: Bool) {
        controlIsEnabled = isEnabled
        if !isEnabled {
            resetInteractionState()
        }
        alphaValue = isEnabled ? 1 : 0.45
        setAccessibilityEnabled(isEnabled)
        needsDisplay = true
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
        guard isPressed, controlIsEnabled else {
            resetInteractionState()
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
        if isHovering || isPressed {
            let alpha: CGFloat = isPressed ? 0.18 : 0.14
            backgroundColor.appKitResolvedColor(in: self, alpha: alpha).setFill()
            NSBezierPath(ovalIn: bounds).fill()
        }

        guard let image = symbolImage(color: foregroundColor) else {
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

    private var backgroundColor: NSColor {
        isDestructive ? .systemRed : .secondaryLabelColor
    }

    private var foregroundColor: NSColor {
        let base: NSColor = isDestructive ? .systemRed : .labelColor
        return base.appKitResolvedColor(in: self, alpha: controlIsEnabled ? 0.80 : 0.35)
    }

    private func symbolImage(color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
            .applying(.init(hierarchicalColor: color))
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    private func resetInteractionState() {
        isPressed = false
        isHovering = false
        needsDisplay = true
    }
}
