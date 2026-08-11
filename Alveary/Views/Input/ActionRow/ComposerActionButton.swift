import AppKit

/// Native primary/destructive composer action button that matches
/// `ProminentActionButtonStyle` sizing, fill, foreground, and interaction states.
final class ComposerActionButton: NSView {
    enum Style {
        case primary
        case destructive
    }

    var actionHandler: (() -> Void)?

    private let style: Style
    private var title = ""
    private var symbolName = ""
    private var controlIsEnabled = true
    private var hidesContent = false
    private var isPressed = false
    private var isHovering = false
    private var firedDuringCurrentPress = false
    private var trackingArea: NSTrackingArea?

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        setContentHuggingPriority(.required, for: .horizontal)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) {
        style = .primary
        super.init(coder: coder)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var isHidden: Bool {
        didSet {
            if isHidden {
                resetInteractionState()
            }
        }
    }

    override var intrinsicContentSize: NSSize {
        let width = ceil(title.size(withAttributes: [.font: buttonFont]).width) + 42
        return NSSize(width: max(style == .primary ? 76 : 72, width), height: 30)
    }

    func configure(
        title: String,
        symbolName: String,
        isEnabled: Bool,
        accessibilityLabel: String,
        hidesContent: Bool = false
    ) {
        self.title = title
        self.symbolName = symbolName
        controlIsEnabled = isEnabled
        self.hidesContent = hidesContent
        if !isEnabled {
            resetInteractionState()
        }
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityEnabled(isEnabled)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func accessibilityPerformPress() -> Bool {
        guard controlIsEnabled else {
            return false
        }
        actionHandler?()
        return true
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
        guard controlIsEnabled else {
            return
        }
        isPressed = true
        firedDuringCurrentPress = false
        needsDisplay = true
        if style == .destructive {
            // Stop is time-sensitive and can immediately replace this button;
            // firing on mouse-down keeps the click from being lost before mouse-up.
            firedDuringCurrentPress = true
            actionHandler?()
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isPressed, controlIsEnabled else {
            isPressed = false
            firedDuringCurrentPress = false
            needsDisplay = true
            return
        }
        isPressed = false
        needsDisplay = true
        if !firedDuringCurrentPress,
           bounds.contains(convert(event.locationInWindow, from: nil)) {
            actionHandler?()
        }
        firedDuringCurrentPress = false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawBackground()
        drawContent()
    }

    private var buttonFont: NSFont {
        .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    }

    private var foregroundColor: NSColor {
        switch style {
        case .primary:
            return .labelColor
        case .destructive:
            return .white
        }
    }

    private var backgroundColor: NSColor {
        switch style {
        case .primary:
            return AppAccentFill.primaryNSColor.appKitResolvedColor(in: self)
        case .destructive:
            return NSColor(red: 0.74, green: 0.18, blue: 0.17, alpha: 1)
        }
    }

    private var backgroundAlpha: CGFloat {
        guard controlIsEnabled else {
            return 0.38
        }
        return (isPressed ? 0.84 : 1) * pressedBodyOpacity
    }

    private func drawBackground() {
        backgroundColor.withAlphaComponent(backgroundAlpha).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: AppCornerRadius.standard, yRadius: AppCornerRadius.standard).fill()
        if isHovering, controlIsEnabled, !isPressed {
            foregroundColor.appKitResolvedColor(in: self, alpha: 0.06 * pressedBodyOpacity).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: AppCornerRadius.standard, yRadius: AppCornerRadius.standard).fill()
        }
    }

    private func drawContent() {
        guard !hidesContent else {
            return
        }
        let foreground = foregroundColor.appKitResolvedColor(in: self, alpha: foregroundAlpha)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: buttonFont,
            .foregroundColor: foreground
        ]
        let titleWidth = ceil(title.size(withAttributes: textAttributes).width)
        let imageSize = NSSize(width: 15, height: 15)
        var contentX = floor((bounds.width - imageSize.width - 6 - titleWidth) / 2)
        if let image = symbolImage(named: symbolName, color: foreground) {
            image.draw(
                in: NSRect(
                    x: contentX,
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
        contentX += imageSize.width + 6
        let titleSize = title.size(withAttributes: textAttributes)
        (title as NSString).draw(
            in: NSRect(
                x: contentX,
                y: floor(bounds.midY - titleSize.height / 2),
                width: titleWidth,
                height: titleSize.height
            ),
            withAttributes: textAttributes
        )
    }

    private func symbolImage(named name: String, color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            .applying(.init(hierarchicalColor: color))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    private var foregroundAlpha: CGFloat {
        (controlIsEnabled ? 1 : 0.78) * pressedBodyOpacity
    }

    private var pressedBodyOpacity: CGFloat {
        isPressed && controlIsEnabled ? 0.94 : 1
    }

    private func resetInteractionState() {
        isPressed = false
        isHovering = false
        firedDuringCurrentPress = false
        needsDisplay = true
    }
}
