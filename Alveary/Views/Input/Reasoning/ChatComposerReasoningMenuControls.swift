import AppKit

@MainActor
class ComposerReasoningMenuInteractiveControl: NSView {
    private var trackingArea: NSTrackingArea?
    private var focusStateIsVisible = false
    private(set) var controlIsEnabled = true
    private(set) var isHovering = false
    private(set) var isPressed = false
    var showsFocusState: Bool { focusStateIsVisible && window?.firstResponder === self }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { controlIsEnabled && !isHidden }
    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }
    override var isHidden: Bool {
        didSet {
            if isHidden {
                releaseFocusAndResetInteraction()
            }
        }
    }
    func configureInteraction(isEnabled: Bool, disabledAlpha: CGFloat) {
        controlIsEnabled = isEnabled
        setAccessibilityEnabled(isEnabled)
        alphaValue = isEnabled ? 1 : disabledAlpha
        if !isEnabled {
            releaseFocusAndResetInteraction()
        }
        needsDisplay = true
    }
    func performControlActivation() {}
    func handleControlKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 36, 49:
            performControlActivation()
            return true
        default:
            return false
        }
    }
    func controlAppearanceDidChange() {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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
        focusStateIsVisible = Self.shouldRevealFocusState(for: NSApp.currentEvent)
        needsDisplay = true
        return true
    }
    override func resignFirstResponder() -> Bool {
        focusStateIsVisible = false
        needsDisplay = true
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
            focusStateIsVisible = false
            resetInteractionState()
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        controlAppearanceDidChange()
        needsDisplay = true
    }
    override func mouseEntered(with event: NSEvent) {
        guard controlIsEnabled else { return }
        isHovering = true
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        isHovering = false
        isPressed = false
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        guard controlIsEnabled else { return }
        window?.makeFirstResponder(self)
        focusStateIsVisible = false
        isPressed = true
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard controlIsEnabled else { return }
        let isInside = eventLocationIsInside(event)
        if isPressed != isInside {
            isPressed = isInside
            needsDisplay = true
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard controlIsEnabled else {
            isPressed = false
            needsDisplay = true
            return
        }
        let shouldActivate = isPressed && eventLocationIsInside(event)
        if shouldActivate {
            resetInteractionState()
            performControlActivation()
        } else {
            isPressed = false
            needsDisplay = true
        }
    }
    override func keyDown(with event: NSEvent) {
        guard controlIsEnabled else { return }
        focusStateIsVisible = true
        needsDisplay = true
        if !handleControlKeyDown(event) {
            super.keyDown(with: event)
        }
    }
    override func accessibilityPerformPress() -> Bool {
        guard controlIsEnabled else { return false }
        performControlActivation()
        return true
    }
    func resetInteractionState() {
        isHovering = false
        isPressed = false
        needsDisplay = true
    }
    static func shouldRevealFocusState(for event: NSEvent?) -> Bool {
        event?.type == .keyDown
    }
    private func releaseFocusAndResetInteraction() {
        focusStateIsVisible = false
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
        resetInteractionState()
    }
    private func eventLocationIsInside(_ event: NSEvent) -> Bool {
        bounds.contains(convert(event.locationInWindow, from: nil))
    }
}

@MainActor
final class ComposerReasoningModelsDisclosureControl: ComposerReasoningMenuInteractiveControl {
    private static let expandedRotation = CGFloat.pi / 2
    private static let title = "Models"
    private let chevronView = NSImageView()
    private let reducesMotion: () -> Bool
    private var onExpansionChange: ((Bool) -> Void)?
    private var hasConfiguration = false
    private var chevronRotation: CGFloat = 0
    private var didRequestChevronRotationAnimation = false
    private var chevronUnrotatedFrame: NSRect?
    private(set) var isExpanded = false
    override var intrinsicContentSize: NSSize {
        NSSize(
            width: ceil(
                ComposerReasoningMenuMetrics.titleLeading +
                    titleDrawingWidth +
                    ComposerReasoningButton.caretTextSpacing +
                    chevronRotationSlotWidth +
                    ComposerReasoningMenuMetrics.titleTrailing
            ),
            height: ComposerReasoningMenuMetrics.rowHeight
        )
    }
    init(reducesMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.reducesMotion = reducesMotion
        super.init(frame: .zero)
        setup()
    }
    required init?(coder: NSCoder) {
        reducesMotion = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        super.init(coder: coder)
        setup()
    }
    func configure(
        isExpanded: Bool,
        isEnabled: Bool,
        animated: Bool,
        onExpansionChange: @escaping (Bool) -> Void
    ) {
        self.onExpansionChange = onExpansionChange
        configureInteraction(isEnabled: isEnabled, disabledAlpha: 0.55)
        let shouldAnimate = hasConfiguration && animated
        setExpanded(isExpanded, animated: shouldAnimate)
        hasConfiguration = true
        updateAppearance()
    }
    func setExpanded(_ isExpanded: Bool, animated: Bool) {
        let previousRotation = chevronRotation
        let didChange = self.isExpanded != isExpanded
        self.isExpanded = isExpanded
        chevronRotation = isExpanded ? Self.expandedRotation : 0
        setAccessibilityExpanded(isExpanded)
        needsLayout = true
        layoutSubtreeIfNeeded()
        applyChevronRotation(from: previousRotation, animated: animated && didChange)
        if didChange, hasConfiguration {
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }
    override func layout() {
        super.layout()
        let chevronSize = chevronDrawingSize
        let rotatedVisualSize = rotatedChevronVisualSize
        let unrotatedFrame = NSRect(
            x: titleVisualFrame.maxX +
                ComposerReasoningButton.caretTextSpacing +
                (rotatedVisualSize.width - chevronSize.width) / 2,
            y: floor((bounds.height - chevronSize.height) / 2),
            width: chevronSize.width,
            height: chevronSize.height
        )
        guard chevronUnrotatedFrame != unrotatedFrame else {
            return
        }
        chevronUnrotatedFrame = unrotatedFrame
        // Assign the unrotated frame in a neutral coordinate space. `NSView.frame`
        // has transformed semantics while `frameCenterRotation` is nonzero, which
        // otherwise shifts a disclosure that is already expanded when first laid out.
        chevronView.frameCenterRotation = 0
        chevronView.frame = unrotatedFrame
        positionChevronView()
    }
    override func controlAppearanceDidChange() {
        updateAppearance()
    }
    override func performControlActivation() {
        toggleExpansion()
    }
    override func handleControlKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 124:
            requestExpansion(true)
            return true
        case 123:
            requestExpansion(false)
            return true
        default:
            return super.handleControlKeyDown(event)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawInteractionBackground()
        drawTitle()
    }
    #if DEBUG
    var debugChevronSymbolName: String { "chevron.right" }
    var debugChevronRotationRadians: CGFloat { chevronRotation }
    var debugTitleVisualFrame: NSRect { titleVisualFrame }
    var debugInteractionBackgroundFrame: NSRect { interactionBackgroundFrame }
    var debugChevronFrame: NSRect { chevronView.frame }
    var debugChevronVisualFrame: NSRect {
        chevronView.convert(chevronView.bounds, to: self)
    }
    var debugTitleChevronVisualGap: CGFloat { debugChevronVisualFrame.minX - debugTitleVisualFrame.maxX }
    var debugChevronRotationSlotMaxX: CGFloat {
        titleVisualFrame.maxX + ComposerReasoningButton.caretTextSpacing + chevronRotationSlotWidth
    }
    var debugChevronTintColor: NSColor? { chevronView.contentTintColor }
    var debugTitleFont: NSFont { ComposerReasoningMenuMetrics.itemFont }
    var debugChevronFrameCenterRotationDegrees: CGFloat { chevronView.frameCenterRotation }
    var debugDidRequestChevronRotationAnimation: Bool { didRequestChevronRotationAnimation }
    var debugIsHovering: Bool { isHovering }
    var debugIsPressed: Bool { isPressed }
    var debugIsFocused: Bool { showsFocusState }
    var debugIsFirstResponder: Bool { window?.firstResponder === self }
    var debugShowsInteractionBackground: Bool { interactionBackgroundAlpha != nil }
    func performActivationForTesting() {
        toggleExpansion()
    }
    #endif
    private func setup() {
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Models")
        setAccessibilityExpanded(false)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        chevronView.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: ComposerReasoningButton.caretMaximumSize, weight: .medium))
        chevronView.imageScaling = .scaleProportionallyDown
        chevronView.setAccessibilityElement(false)
        chevronView.wantsLayer = true
        addSubview(chevronView)
        updateAppearance()
    }
    private var titleDrawingWidth: CGFloat {
        ceil((Self.title as NSString).size(withAttributes: titleAttributes).width)
    }
    private var titleVisualFrame: NSRect {
        let titleHeight = (Self.title as NSString).size(withAttributes: titleAttributes).height
        return NSRect(
            x: ComposerReasoningMenuMetrics.titleLeading,
            y: floor((bounds.height - titleHeight) / 2),
            width: titleDrawingWidth,
            height: titleHeight
        )
    }
    private var titleAttributes: [NSAttributedString.Key: Any] {
        [
            .font: ComposerReasoningMenuMetrics.itemFont,
            .foregroundColor: NSColor.labelColor.appKitResolvedColor(
                in: self,
                alpha: controlIsEnabled ? 0.86 : 0.42
            ),
            .paragraphStyle: ComposerReasoningMenuMetrics.truncatingParagraphStyle
        ]
    }
    private var chevronDrawingSize: NSSize {
        guard let image = chevronView.image,
              image.size.width > 0,
              image.size.height > 0 else {
            return NSSize(
                width: ComposerReasoningButton.caretMaximumSize,
                height: ComposerReasoningButton.caretMaximumSize
            )
        }
        let maximumSize = ComposerReasoningButton.caretMaximumSize
        let scale = min(maximumSize / image.size.width, maximumSize / image.size.height)
        return NSSize(
            width: ceil(image.size.width * scale),
            height: ceil(image.size.height * scale)
        )
    }
    private var chevronRotationSlotWidth: CGFloat {
        max(chevronDrawingSize.width, chevronDrawingSize.height)
    }
    private var rotatedChevronVisualSize: NSSize {
        let drawingSize = chevronDrawingSize
        let cosine = abs(cos(chevronRotation))
        let sine = abs(sin(chevronRotation))
        return NSSize(
            width: drawingSize.width * cosine + drawingSize.height * sine,
            height: drawingSize.width * sine + drawingSize.height * cosine
        )
    }
    private func updateAppearance() {
        chevronView.contentTintColor = NSColor.labelColor.appKitResolvedColor(
            in: self,
            alpha: controlIsEnabled ? 0.72 : 0.32
        )
        needsDisplay = true
    }
    private func drawTitle() {
        (Self.title as NSString).draw(in: titleVisualFrame, withAttributes: titleAttributes)
    }
    private func toggleExpansion() {
        requestExpansion(!isExpanded)
    }
    private func requestExpansion(_ shouldExpand: Bool) {
        guard controlIsEnabled, isExpanded != shouldExpand else {
            return
        }
        setExpanded(shouldExpand, animated: true)
        onExpansionChange?(shouldExpand)
    }
    private func applyChevronRotation(from previousRotation: CGFloat, animated: Bool) {
        let targetDegrees = chevronRotation * 180 / .pi
        guard animated, !reducesMotion() else {
            didRequestChevronRotationAnimation = false
            chevronView.frameCenterRotation = targetDegrees
            return
        }
        didRequestChevronRotationAnimation = true
        chevronView.frameCenterRotation = previousRotation * 180 / .pi
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ComposerReasoningMenuMetrics.disclosureAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            chevronView.animator().frameCenterRotation = targetDegrees
        }
    }
    private func positionChevronView() {
        chevronView.frameCenterRotation = chevronRotation * 180 / .pi
    }
    private func drawInteractionBackground() {
        guard controlIsEnabled else {
            return
        }
        let path = NSBezierPath(roundedRect: interactionBackgroundFrame, xRadius: 7, yRadius: 7)
        if let alpha = interactionBackgroundAlpha {
            NSColor.labelColor.appKitResolvedColor(in: self, alpha: alpha).setFill()
            path.fill()
        }
        if showsFocusState {
            AppAccentFill.primaryNSColor.appKitResolvedColor(in: self, alpha: 0.22).setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }
    private var interactionBackgroundFrame: NSRect {
        bounds.insetBy(dx: 2, dy: 2)
    }
    private var interactionBackgroundAlpha: CGFloat? {
        guard controlIsEnabled else {
            return nil
        }
        if isPressed {
            return 0.14
        }
        if isHovering || showsFocusState {
            return 0.09
        }
        return nil
    }
}
