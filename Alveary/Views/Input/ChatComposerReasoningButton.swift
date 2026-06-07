import AppKit

@MainActor
final class ComposerReasoningButton: NSView {
    static let minWidth: CGFloat = 64
    static let maxWidth: CGFloat = 180
    private static let horizontalPadding: CGFloat = 10
    private static let chevronSlotWidth: CGFloat = 18
    private static let chevronMaxSize: CGFloat = 10
    private static let progressIndicatorSize: CGFloat = 12
    // SF Symbols' chevron bounds are geometrically centered but read high next
    // to the mixed bold/regular text run, so align it optically instead.
    private static let chevronOpticalYOffset: CGFloat = 1.5

    var actionHandler: (() -> Void)?

    private var selection: ChatComposerActionRowView.ReasoningSelection?
    private var controlIsEnabled = true
    private var controlHeight = ChatComposerActionRowView.defaultSettingsControlHeight
    private var showsProgress = false
    private var isPressed = false
    private var isHovering = false
    private var trackingArea: NSTrackingArea?
    private let progressIndicator = NSProgressIndicator()

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { controlIsEnabled }
    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override var intrinsicContentSize: NSSize {
        let contentWidth = measuredLabelWidth + Self.horizontalPadding * 2 + Self.chevronSlotWidth
        return NSSize(
            width: min(Self.maxWidth, max(Self.minWidth, ceil(contentWidth))),
            height: controlHeight
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(
        selection: ChatComposerActionRowView.ReasoningSelection,
        height: CGFloat,
        isEnabled: Bool,
        showsProgress: Bool,
        actionHandler: @escaping () -> Void
    ) {
        self.selection = selection
        controlHeight = height
        controlIsEnabled = isEnabled
        self.showsProgress = showsProgress
        self.actionHandler = actionHandler
        if !isEnabled {
            resetInteractionState()
        }
        setAccessibilityEnabled(isEnabled)
        setAccessibilityValue(selection.accessibilityValue)
        updateProgressIndicator()
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

    #if DEBUG
    var debugShowsProgress: Bool { showsProgress && !progressIndicator.isHidden }
    var debugTextAlpha: CGFloat { textAlpha }
    #endif

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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        progressIndicator.frame = NSRect(
            x: bounds.maxX - Self.horizontalPadding - Self.progressIndicatorSize,
            y: floor((bounds.height - Self.progressIndicatorSize) / 2),
            width: Self.progressIndicatorSize,
            height: Self.progressIndicatorSize
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.labelColor.appKitResolvedColor(in: self, alpha: backgroundAlpha).setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        path.fill()
        if window?.firstResponder === self, controlIsEnabled {
            AppAccentFill.primaryNSColor.appKitResolvedColor(in: self, alpha: 0.22).setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
        drawLabel()
        if !showsProgress {
            drawChevron()
        }
    }

    private var measuredLabelWidth: CGFloat {
        guard let selection else {
            return 0
        }
        let modelWidth = selection.modelTitle.size(withAttributes: [.font: modelFont]).width
        guard !selection.effortOptions.isEmpty else {
            return modelWidth
        }
        let effortWidth = selection.effortTitle.size(withAttributes: [.font: effortFont]).width
        return modelWidth + 6 + effortWidth
    }

    private var modelFont: NSFont {
        NSFontManager.shared.convert(NSFont.preferredFont(forTextStyle: .body), toHaveTrait: .boldFontMask)
    }

    private var effortFont: NSFont {
        NSFont.preferredFont(forTextStyle: .body)
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

    private var textAlpha: CGFloat {
        controlIsEnabled || showsProgress ? 0.9 : 0.26
    }

    private var subtleTextAlpha: CGFloat {
        controlIsEnabled || showsProgress ? 0.62 : 0.22
    }

    private func setup() {
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Reasoning")
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.isHidden = true
        addSubview(progressIndicator)
    }

    private func drawLabel() {
        guard let selection else {
            return
        }
        let contentMaxX = bounds.maxX - Self.horizontalPadding - Self.chevronSlotWidth
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let modelAttributes: [NSAttributedString.Key: Any] = [
            .font: modelFont,
            .foregroundColor: NSColor.labelColor.appKitResolvedColor(in: self, alpha: textAlpha),
            .paragraphStyle: paragraph
        ]
        let effortAttributes: [NSAttributedString.Key: Any] = [
            .font: effortFont,
            .foregroundColor: NSColor.secondaryLabelColor.appKitResolvedColor(in: self, alpha: subtleTextAlpha),
            .paragraphStyle: paragraph
        ]
        let modelHeight = selection.modelTitle.size(withAttributes: modelAttributes).height
        let labelY = floor((bounds.height - modelHeight) / 2)

        if selection.effortOptions.isEmpty {
            (selection.modelTitle as NSString).draw(
                in: NSRect(
                    x: Self.horizontalPadding,
                    y: labelY,
                    width: max(0, contentMaxX - Self.horizontalPadding),
                    height: modelHeight
                ),
                withAttributes: modelAttributes
            )
            return
        }

        let effortWidth = ceil(selection.effortTitle.size(withAttributes: effortAttributes).width)
        let effortX = max(Self.horizontalPadding, contentMaxX - effortWidth)
        let modelWidth = max(0, effortX - Self.horizontalPadding - 6)
        (selection.modelTitle as NSString).draw(
            in: NSRect(x: Self.horizontalPadding, y: labelY, width: modelWidth, height: modelHeight),
            withAttributes: modelAttributes
        )
        (selection.effortTitle as NSString).draw(
            in: NSRect(x: effortX, y: labelY, width: effortWidth, height: modelHeight),
            withAttributes: effortAttributes
        )
    }

    private func drawChevron() {
        guard let image = symbolImage(named: "chevron.down", pointSize: Self.chevronMaxSize, color: chevronColor) else {
            return
        }
        let drawSize = symbolDrawingSize(for: image, maxSize: Self.chevronMaxSize)
        image.draw(
            in: NSRect(
                x: bounds.maxX - Self.horizontalPadding - drawSize.width,
                y: floor((bounds.height - drawSize.height) / 2) + Self.chevronOpticalYOffset,
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

    private func symbolDrawingSize(for image: NSImage, maxSize: CGFloat) -> NSSize {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSSize(width: maxSize, height: maxSize)
        }
        let scale = min(maxSize / imageSize.width, maxSize / imageSize.height)
        return NSSize(width: ceil(imageSize.width * scale), height: ceil(imageSize.height * scale))
    }

    private var chevronColor: NSColor {
        NSColor.secondaryLabelColor.appKitResolvedColor(in: self, alpha: controlIsEnabled ? 0.72 : 0.18)
    }

    private func symbolImage(named name: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            .applying(.init(hierarchicalColor: color))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    private func updateProgressIndicator() {
        progressIndicator.isHidden = !showsProgress
        if showsProgress {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }
        needsLayout = true
    }

    private func resetInteractionState() {
        isPressed = false
        isHovering = false
        needsDisplay = true
    }
}
