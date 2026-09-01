import AppKit

@MainActor
final class ComposerReasoningMenuRowView: NSView {
    private var configuration: Configuration?
    private var trackingArea: NSTrackingArea?
    private var geometryObservers: [NSObjectProtocol] = []
    private var focusStateIsVisible = false
    private var isHovering = false
    private var isPressed = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { configuration?.isEnabled == true }
    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    func configure(_ configuration: Configuration) {
        let previousSelection = self.configuration?.isSelected
        self.configuration = configuration
        setAccessibilityLabel(configuration.accessibilityLabel)
        setAccessibilityEnabled(configuration.isEnabled)
        setAccessibilityValue(configuration.isSelected ? "Selected" : nil)
        setAccessibilitySelected(configuration.isSelected)
        alphaValue = configuration.isEnabled ? 1 : 0.55
        if !configuration.isEnabled {
            focusStateIsVisible = false
            resetInteractionState()
        }
        if let previousSelection, previousSelection != configuration.isSelected {
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
        needsDisplay = true
    }

    #if DEBUG
    /// Stands in for `mouseLocationOutsideOfEventStream` (and its key-window guard) so tests can
    /// steer `refreshHoverFromPointerLocation()` without a real pointer.
    static var debugPointerLocationInWindowOverride: NSPoint?
    var debugIconName: String? { configuration?.iconName }
    var debugIconRotationRadians: CGFloat { configuration?.iconRotationRadians ?? 0 }
    var debugTrailingIconName: String? { configuration?.trailingIconName }
    var debugSubtitle: String? { configuration?.subtitle }
    var debugIsWarning: Bool { configuration?.isWarning == true }
    var debugShowsInteractionBackground: Bool { interactionBackgroundAlpha != nil }
    var debugLeadingIconLeft: CGFloat? {
        configuration?.iconName == nil
            ? nil
            : ComposerReasoningMenuMetrics.iconLeading + ComposerReasoningMenuMetrics.iconOpticalLeadingAdjustment
    }
    var debugTitleLeading: CGFloat? {
        configuration.map { titleLeading(for: $0) }
    }
    var debugTitleVisualFrame: NSRect? {
        guard let configuration else {
            return nil
        }
        let attributes = titleAttributes(for: configuration)
        let titleSize = configuration.title.size(withAttributes: attributes)
        let titleRect = titleTextRect(for: configuration, titleHeight: titleSize.height)
        return NSRect(
            x: titleRect.minX,
            y: floor((bounds.height - titleRect.height) / 2),
            width: ceil(titleSize.width),
            height: titleRect.height
        )
    }
    var debugTitleFont: NSFont { ComposerReasoningMenuMetrics.itemFont }
    var debugInteractionBackgroundFrame: NSRect { interactionBackgroundFrame }
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func becomeFirstResponder() -> Bool {
        guard configuration?.isEnabled == true else {
            return false
        }
        focusStateIsVisible = ComposerReasoningMenuInteractiveControl.shouldRevealFocusState(for: NSApp.currentEvent)
        if configuration?.showsFocusBackground == true {
            scrollToVisible(bounds)
        }
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        focusStateIsVisible = false
        needsDisplay = true
        return true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        // Released on the way out, not in `deinit`, which cannot touch main-actor state — and a
        // closing window does not always run `viewDidMoveToWindow` for its views again.
        guard newWindow == nil else {
            return
        }
        releaseGeometryObservers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            focusStateIsVisible = false
            resetInteractionState()
            return
        }
        observeEnclosingScroll()
        refreshHoverFromPointerLocation()
    }

    override func mouseEntered(with event: NSEvent) {
        guard configuration?.isEnabled == true else {
            return
        }
        setHovering(true)
    }

    override func mouseExited(with event: NSEvent) {
        resetInteractionState()
    }

    override func mouseDown(with event: NSEvent) {
        guard configuration?.isEnabled == true else {
            return
        }
        window?.makeFirstResponder(self)
        focusStateIsVisible = false
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard configuration?.isEnabled == true else {
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
        configuration?.action()
    }

    override func keyDown(with event: NSEvent) {
        guard configuration?.isEnabled == true else {
            return
        }
        focusStateIsVisible = true
        needsDisplay = true
        switch event.keyCode {
        case 36, 49:
            configuration?.action()
        case 124 where configuration?.activatesWithRightArrow == true:
            configuration?.action()
        case 53:
            configuration?.cancelAction()
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard configuration?.isEnabled == true else {
            return false
        }
        configuration?.action()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawBackground()
        drawIcon()
        drawTitle()
        drawTrailingIcon()
    }

    private func drawBackground() {
        guard configuration?.isEnabled == true else {
            return
        }
        guard let alpha = interactionBackgroundAlpha else {
            return
        }
        NSColor.labelColor.appKitResolvedColor(in: self, alpha: alpha).setFill()
        NSBezierPath(roundedRect: interactionBackgroundFrame, xRadius: 7, yRadius: 7).fill()
    }

    private var interactionBackgroundFrame: NSRect {
        bounds.insetBy(dx: 2, dy: 2)
    }

    private var interactionBackgroundAlpha: CGFloat? {
        guard configuration?.isEnabled == true else {
            return nil
        }
        if isPressed {
            return 0.14
        }
        if isHovering {
            return 0.09
        }
        if configuration?.showsFocusBackground == true,
           focusStateIsVisible,
           window?.firstResponder === self {
            return 0.09
        }
        return nil
    }

    private func drawIcon() {
        guard let configuration,
              let iconName = configuration.iconName,
              let image = symbolImage(
                named: iconName,
                pointSize: ComposerReasoningMenuMetrics.leadingIconPointSize,
                color: iconColor(for: configuration)
        ) else {
            return
        }
        let drawSize = symbolDrawingSize(for: image, maxSize: ComposerReasoningMenuMetrics.iconSlotSize)
        drawImage(
            image,
            in: NSRect(
                x: ComposerReasoningMenuMetrics.iconLeading + floor((ComposerReasoningMenuMetrics.iconSlotSize - drawSize.width) / 2),
                y: floor((bounds.height - drawSize.height) / 2),
                width: drawSize.width,
                height: drawSize.height
            ),
            rotationRadians: configuration.iconRotationRadians
        )
    }

    private func drawTitle() {
        guard let configuration else {
            return
        }
        let attributes = titleAttributes(for: configuration)
        let titleSize = configuration.title.size(withAttributes: attributes)
        let titleRect = titleTextRect(for: configuration, titleHeight: titleSize.height)
        guard let subtitle = configuration.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !subtitle.isEmpty else {
            drawCenteredTitle(configuration.title, in: titleRect, attributes: attributes)
            return
        }

        drawStackedTitle(
            configuration.title,
            subtitle: subtitle,
            titleRect: titleRect,
            titleAttributes: attributes,
            subtitleAttributes: subtitleAttributes(for: configuration)
        )
    }

    private func titleTextRect(for configuration: Configuration, titleHeight: CGFloat) -> NSRect {
        // Multi-line subtitles always reserve the trailing icon slot so wrap
        // width (and therefore measured row height) cannot change when the
        // selection checkmark appears or disappears.
        let reservesTrailing = configuration.trailingIconName != nil || configuration.subtitleLineLimit > 1
        let trailingReserved: CGFloat = reservesTrailing ? ComposerReasoningMenuMetrics.trailingIconReservedWidth : 0
        let leading = titleLeading(for: configuration)
        return NSRect(
            x: leading,
            y: 0,
            width: max(
                0,
                bounds.width -
                    leading -
                    ComposerReasoningMenuMetrics.titleTrailing -
                    trailingReserved
            ),
            height: titleHeight
        )
    }

    private func titleLeading(for configuration: Configuration) -> CGFloat {
        configuration.iconName == nil
            ? ComposerReasoningMenuMetrics.titleLeading
            : ComposerReasoningMenuMetrics.iconTitleLeading
    }

    private func drawCenteredTitle(
        _ title: String,
        in titleRect: NSRect,
        attributes: [NSAttributedString.Key: Any]
    ) {
        (title as NSString).draw(
            in: NSRect(
                x: titleRect.minX,
                y: floor((bounds.height - titleRect.height) / 2),
                width: titleRect.width,
                height: titleRect.height
            ),
            withAttributes: attributes
        )
    }

    private func drawStackedTitle(
        _ title: String,
        subtitle: String,
        titleRect: NSRect,
        titleAttributes: [NSAttributedString.Key: Any],
        subtitleAttributes: [NSAttributedString.Key: Any]
    ) {
        let lineLimit = configuration?.subtitleLineLimit ?? 1
        let subtitleHeight = Self.subtitleHeight(
            subtitle,
            availableWidth: titleRect.width,
            lineLimit: lineLimit
        )
        let groupHeight = titleRect.height + ComposerReasoningMenuMetrics.subtitleSpacing + subtitleHeight
        let titleY = floor((bounds.height - groupHeight) / 2)
        (title as NSString).draw(
            in: NSRect(
                x: titleRect.minX,
                y: titleY,
                width: titleRect.width,
                height: titleRect.height
            ),
            withAttributes: titleAttributes
        )
        let subtitleRect = NSRect(
            x: titleRect.minX,
            y: titleY + titleRect.height + ComposerReasoningMenuMetrics.subtitleSpacing,
            width: titleRect.width,
            height: subtitleHeight
        )
        if lineLimit > 1 {
            (subtitle as NSString).draw(
                with: subtitleRect,
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: subtitleAttributes
            )
        } else {
            (subtitle as NSString).draw(in: subtitleRect, withAttributes: subtitleAttributes)
        }
    }

    private func drawTrailingIcon() {
        guard let trailingIconName = configuration?.trailingIconName,
              let image = symbolImage(
                named: trailingIconName,
                pointSize: ComposerReasoningMenuMetrics.iconPointSize,
                color: NSColor.labelColor.appKitResolvedColor(in: self, alpha: 0.72)
              ) else {
            return
        }
        let drawSize = symbolDrawingSize(for: image, maxSize: ComposerReasoningMenuMetrics.iconPointSize)
        image.draw(
            in: NSRect(
                x: bounds.maxX - ComposerReasoningMenuMetrics.trailingIconInset - drawSize.width,
                y: floor((bounds.height - drawSize.height) / 2),
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

}

private extension ComposerReasoningMenuRowView {
    /// Scrolling moves rows under a stationary pointer with no mouse event, and keyboard focus
    /// does the same through `becomeFirstResponder()`'s `scrollToVisible` — AppKit delivers no
    /// `mouseExited` for either, so every row the cursor passes over would keep its hover
    /// highlight. Re-deriving hover from the pointer's actual location on each scroll or resize
    /// frame is what unsticks it. Rows in popovers without a scroll view have nothing to observe.
    func observeEnclosingScroll() {
        releaseGeometryObservers()
        guard let clipView = enclosingScrollView?.contentView else {
            return
        }
        clipView.postsBoundsChangedNotifications = true
        clipView.postsFrameChangedNotifications = true
        geometryObservers = [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification]
            .map { name in
                NotificationCenter.default.addObserver(forName: name, object: clipView, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.refreshHoverFromPointerLocation()
                    }
                }
            }
    }

    func releaseGeometryObservers() {
        for observer in geometryObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        geometryObservers = []
    }

    func refreshHoverFromPointerLocation() {
        guard configuration?.isEnabled == true, let pointerInWindow = pointerLocationInWindow() else {
            setHovering(false)
            return
        }
        let pointer = convert(pointerInWindow, from: nil)
        // The pointer can sit inside this view's bounds while the view is scrolled out of the
        // clip view, so the visible rect has to agree before the row claims the highlight.
        setHovering(bounds.contains(pointer) && visibleRect.contains(pointer))
    }

    func pointerLocationInWindow() -> NSPoint? {
        #if DEBUG
        if let override = Self.debugPointerLocationInWindowOverride {
            return override
        }
        #endif
        guard let window, window.isKeyWindow else {
            return nil
        }
        return window.mouseLocationOutsideOfEventStream
    }

    func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else {
            return
        }
        isHovering = hovering
        needsDisplay = true
    }

    func resetInteractionState() {
        isHovering = false
        isPressed = false
        needsDisplay = true
    }
}
