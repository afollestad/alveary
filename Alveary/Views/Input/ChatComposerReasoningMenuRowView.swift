import AppKit

@MainActor
final class ComposerReasoningMenuRowView: NSView {
    struct Configuration {
        let title: String
        let subtitle: String?
        let iconName: String?
        let trailingIconName: String?
        let accessibilityLabel: String
        let isSelected: Bool
        let isEnabled: Bool
        let isWarning: Bool
        let action: () -> Void
        let hoverAction: (() -> Void)?
        var exitAction: (() -> Void)?
        let cancelAction: () -> Void

        init(
            title: String,
            subtitle: String? = nil,
            iconName: String?,
            trailingIconName: String?,
            accessibilityLabel: String,
            isSelected: Bool,
            isEnabled: Bool,
            isWarning: Bool = false,
            action: @escaping () -> Void,
            hoverAction: (() -> Void)?,
            exitAction: (() -> Void)? = nil,
            cancelAction: @escaping () -> Void
        ) {
            self.title = title
            self.subtitle = subtitle
            self.iconName = iconName
            self.trailingIconName = trailingIconName
            self.accessibilityLabel = accessibilityLabel
            self.isSelected = isSelected
            self.isEnabled = isEnabled
            self.isWarning = isWarning
            self.action = action
            self.hoverAction = hoverAction
            self.exitAction = exitAction
            self.cancelAction = cancelAction
        }
    }

    var onHoverEntered: (() -> Void)?

    private var configuration: Configuration?
    private var trackingArea: NSTrackingArea?
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
        self.configuration = configuration
        setAccessibilityLabel(configuration.accessibilityLabel)
        setAccessibilityEnabled(configuration.isEnabled)
        setAccessibilityValue(configuration.isSelected ? "Selected" : nil)
        setAccessibilitySelected(configuration.isSelected)
        alphaValue = configuration.isEnabled ? 1 : 0.55
        if !configuration.isEnabled {
            resetInteractionState()
        }
        needsDisplay = true
    }

    #if DEBUG
    var debugIconName: String? { configuration?.iconName }
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

    override func mouseEntered(with event: NSEvent) {
        guard configuration?.isEnabled == true else {
            return
        }
        isHovering = true
        needsDisplay = true
        onHoverEntered?()
        configuration?.hoverAction?()
    }

    override func mouseExited(with event: NSEvent) {
        resetInteractionState()
        configuration?.exitAction?()
    }

    override func mouseDown(with event: NSEvent) {
        guard configuration?.isEnabled == true else {
            return
        }
        window?.makeFirstResponder(self)
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
        switch event.keyCode {
        case 36, 49, 124:
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
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 7, yRadius: 7).fill()
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
        let drawSize = image.size
        image.draw(
            in: NSRect(
                x: ComposerReasoningMenuMetrics.iconLeading,
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
        let trailingReserved: CGFloat = configuration.trailingIconName == nil ? 0 : ComposerReasoningMenuMetrics.trailingIconReservedWidth
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
        let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
        let groupHeight = titleRect.height + ComposerReasoningMenuMetrics.subtitleSpacing + subtitleSize.height
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
        (subtitle as NSString).draw(
            in: NSRect(
                x: titleRect.minX,
                y: titleY + titleRect.height + ComposerReasoningMenuMetrics.subtitleSpacing,
                width: titleRect.width,
                height: subtitleSize.height
            ),
            withAttributes: subtitleAttributes
        )
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

    private func symbolImage(named name: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: pointSize,
            weight: .semibold
        ).applying(.init(paletteColors: [color, color, color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    private func iconColor(for configuration: Configuration) -> NSColor {
        let color: NSColor = configuration.isWarning ? .systemOrange : .labelColor
        return color.appKitResolvedColor(in: self, alpha: configuration.isEnabled ? 0.72 : 0.32)
    }

    private func titleAttributes(for configuration: Configuration) -> [NSAttributedString.Key: Any] {
        let color: NSColor = configuration.isWarning ? .systemOrange : .labelColor
        return [
            .font: ComposerReasoningMenuMetrics.itemFont,
            .foregroundColor: color.appKitResolvedColor(in: self, alpha: configuration.isEnabled ? 0.86 : 0.42),
            .paragraphStyle: ComposerReasoningMenuMetrics.truncatingParagraphStyle
        ]
    }

    private func subtitleAttributes(for configuration: Configuration) -> [NSAttributedString.Key: Any] {
        [
            .font: ComposerReasoningMenuMetrics.subtitleFont,
            .foregroundColor: NSColor.secondaryLabelColor.appKitResolvedColor(in: self, alpha: configuration.isEnabled ? 0.68 : 0.32),
            .paragraphStyle: ComposerReasoningMenuMetrics.truncatingParagraphStyle
        ]
    }

    private func symbolDrawingSize(for image: NSImage, maxSize: CGFloat) -> NSSize {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSSize(width: maxSize, height: maxSize)
        }
        let scale = min(maxSize / imageSize.width, maxSize / imageSize.height)
        return NSSize(width: ceil(imageSize.width * scale), height: ceil(imageSize.height * scale))
    }

    private func resetInteractionState() {
        isHovering = false
        isPressed = false
        needsDisplay = true
    }
}
