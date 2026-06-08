import AppKit

@MainActor
class ComposerCompactDropdownButton: NSView {
    var actionHandler: (() -> Void)?

    var controlIsEnabled = true
    var controlHeight = ChatComposerActionRowView.defaultSettingsControlHeight

    var minimumDropdownWidth: CGFloat { 64 }
    var maximumDropdownWidth: CGFloat { 180 }
    var horizontalPadding: CGFloat { 8 }
    var chevronSlotWidth: CGFloat { 18 }
    var chevronMaxSize: CGFloat { 10 }
    var chevronOpticalYOffset: CGFloat { 1.5 }
    var reservesTrailingSlot: Bool { true }
    var drawsChevron: Bool { true }
    var measuredContentWidth: CGFloat { 0 }

    private var isPressed = false
    private var isHovering = false
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { controlIsEnabled }
    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override var intrinsicContentSize: NSSize {
        let trailingWidth = reservesTrailingSlot ? chevronSlotWidth : 0
        let contentWidth = measuredContentWidth + horizontalPadding * 2 + trailingWidth
        return NSSize(
            width: min(maximumDropdownWidth, max(minimumDropdownWidth, ceil(contentWidth))),
            height: controlHeight
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupDropdownButton()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDropdownButton()
    }

    func configureBase(
        height: CGFloat,
        isEnabled: Bool,
        actionHandler: @escaping () -> Void
    ) {
        controlHeight = height
        controlIsEnabled = isEnabled
        self.actionHandler = actionHandler
        if !isEnabled {
            resetInteractionState()
        }
        setAccessibilityEnabled(isEnabled)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    func releaseMenuFocusIfNeeded() {
        isPressed = false
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
        needsDisplay = true
    }

    func setupDropdownButton() {
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
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

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
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
        window?.makeFirstResponder(self)
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard controlIsEnabled else {
            isPressed = false
            needsDisplay = true
            return
        }
        let wasPressed = isPressed
        isPressed = false
        needsDisplay = true
        guard wasPressed, bounds.contains(convert(event.locationInWindow, from: nil)) else {
            return
        }
        actionHandler?()
    }

    override func keyDown(with event: NSEvent) {
        guard controlIsEnabled else {
            return
        }
        switch event.keyCode {
        case 36, 49:
            actionHandler?()
        default:
            super.keyDown(with: event)
        }
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawChrome()
        drawContent(in: contentDrawingRect)
        if drawsChevron {
            drawChevron()
        }
    }

    func drawContent(in rect: NSRect) {}

    var contentDrawingRect: NSRect {
        let trailingWidth = reservesTrailingSlot ? chevronSlotWidth : 0
        return NSRect(
            x: horizontalPadding,
            y: 0,
            width: max(0, bounds.width - horizontalPadding * 2 - trailingWidth),
            height: bounds.height
        )
    }

    var textAlpha: CGFloat {
        controlIsEnabled ? 0.9 : 0.26
    }

    var subtleTextAlpha: CGFloat {
        controlIsEnabled ? 0.62 : 0.22
    }

    func symbolImage(named name: String, pointSize: CGFloat, color: NSColor, weight: NSFont.Weight = .medium) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(.init(hierarchicalColor: color))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    func symbolDrawingSize(for image: NSImage, maxSize: CGFloat) -> NSSize {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSSize(width: maxSize, height: maxSize)
        }
        let scale = min(maxSize / imageSize.width, maxSize / imageSize.height)
        return NSSize(width: ceil(imageSize.width * scale), height: ceil(imageSize.height * scale))
    }

    func resetInteractionState() {
        isPressed = false
        isHovering = false
        needsDisplay = true
    }

    private func drawChrome() {
        NSColor.labelColor.appKitResolvedColor(in: self, alpha: backgroundAlpha).setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        path.fill()
        if window?.firstResponder === self, controlIsEnabled {
            AppAccentFill.primaryNSColor.appKitResolvedColor(in: self, alpha: 0.22).setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private var backgroundAlpha: CGFloat {
        guard controlIsEnabled else {
            return 0
        }
        if isPressed {
            return 0.18
        }
        if isHovering || window?.firstResponder === self {
            return 0.13
        }
        return 0
    }

    private func drawChevron() {
        guard let image = symbolImage(named: "chevron.down", pointSize: chevronMaxSize, color: chevronColor) else {
            return
        }
        let drawSize = symbolDrawingSize(for: image, maxSize: chevronMaxSize)
        image.draw(
            in: NSRect(
                x: bounds.maxX - horizontalPadding - drawSize.width,
                y: floor((bounds.height - drawSize.height) / 2) + chevronOpticalYOffset,
                width: drawSize.width,
                height: drawSize.height
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
    }

    private var chevronColor: NSColor {
        NSColor.secondaryLabelColor.appKitResolvedColor(in: self, alpha: controlIsEnabled ? 0.72 : 0.18)
    }
}
