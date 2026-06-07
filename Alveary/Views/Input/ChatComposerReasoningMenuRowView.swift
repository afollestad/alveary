import AppKit

@MainActor
final class ComposerReasoningMenuRowView: NSView {
    struct Configuration {
        let title: String
        let iconName: String?
        let trailingIconName: String?
        let accessibilityLabel: String
        let isSelected: Bool
        let isEnabled: Bool
        let action: () -> Void
        let hoverAction: (() -> Void)?
        var exitAction: (() -> Void)?
        let cancelAction: () -> Void

        init(
            title: String,
            iconName: String?,
            trailingIconName: String?,
            accessibilityLabel: String,
            isSelected: Bool,
            isEnabled: Bool,
            action: @escaping () -> Void,
            hoverAction: (() -> Void)?,
            exitAction: (() -> Void)? = nil,
            cancelAction: @escaping () -> Void
        ) {
            self.title = title
            self.iconName = iconName
            self.trailingIconName = trailingIconName
            self.accessibilityLabel = accessibilityLabel
            self.isSelected = isSelected
            self.isEnabled = isEnabled
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
    var debugShowsInteractionBackground: Bool { interactionBackgroundAlpha != nil }
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
        guard let iconName = configuration?.iconName,
              let image = symbolImage(named: iconName) else {
            return
        }
        let drawSize = symbolDrawingSize(for: image, maxSize: ComposerReasoningMenuMetrics.iconPointSize)
        image.draw(
            in: NSRect(
                x: ComposerReasoningMenuMetrics.iconLeading +
                    floor((ComposerReasoningMenuMetrics.iconSlotSize - drawSize.width) / 2),
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
        let attributes: [NSAttributedString.Key: Any] = [
            .font: ComposerReasoningMenuMetrics.itemFont,
            .foregroundColor: NSColor.labelColor.appKitResolvedColor(in: self, alpha: configuration.isEnabled ? 0.86 : 0.42),
            .paragraphStyle: ComposerReasoningMenuMetrics.truncatingParagraphStyle
        ]
        let titleSize = configuration.title.size(withAttributes: attributes)
        let trailingReserved: CGFloat = configuration.trailingIconName == nil ? 0 : ComposerReasoningMenuMetrics.trailingIconReservedWidth
        (configuration.title as NSString).draw(
            in: NSRect(
                x: ComposerReasoningMenuMetrics.titleLeading,
                y: floor((bounds.height - titleSize.height) / 2),
                width: max(
                    0,
                    bounds.width -
                        ComposerReasoningMenuMetrics.titleLeading -
                        ComposerReasoningMenuMetrics.titleTrailing -
                        trailingReserved
                ),
                height: titleSize.height
            ),
            withAttributes: attributes
        )
    }

    private func drawTrailingIcon() {
        guard let trailingIconName = configuration?.trailingIconName,
              let image = symbolImage(named: trailingIconName) else {
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

    private func symbolImage(named name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: ComposerReasoningMenuMetrics.iconPointSize,
            weight: .medium
        ).applying(.init(hierarchicalColor: NSColor.labelColor.appKitResolvedColor(in: self, alpha: 0.72)))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
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

@MainActor
final class ComposerReasoningHeaderView: NSTextField {
    init(title: String) {
        super.init(frame: .zero)
        stringValue = title
        isEditable = false
        isBordered = false
        drawsBackground = false
        font = .preferredFont(forTextStyle: .caption1)
        textColor = .secondaryLabelColor
        setAccessibilityElement(false)
    }

    override var isFlipped: Bool { true }

    required init?(coder: NSCoder) {
        nil
    }

    #if DEBUG
    var debugTitleDrawingRect: NSRect {
        titleDrawingRect(with: titleAttributes)
    }
    #endif

    override func draw(_ dirtyRect: NSRect) {
        let attributes = titleAttributes
        (stringValue as NSString).draw(in: titleDrawingRect(with: attributes), withAttributes: attributes)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private var titleAttributes: [NSAttributedString.Key: Any] {
        [
            .font: font ?? .preferredFont(forTextStyle: .caption1),
            .foregroundColor: NSColor.secondaryLabelColor.appKitResolvedColor(in: self, alpha: 1),
            .paragraphStyle: ComposerReasoningMenuMetrics.truncatingParagraphStyle
        ]
    }

    private func titleDrawingRect(with attributes: [NSAttributedString.Key: Any]) -> NSRect {
        let titleSize = stringValue.size(withAttributes: attributes)
        return NSRect(
            x: 0,
            y: max(0, floor(bounds.height - titleSize.height)),
            width: bounds.width,
            height: titleSize.height
        )
    }
}

enum ComposerReasoningMenuMetrics {
    static let width: CGFloat = 244
    static let modelWidth: CGFloat = 260
    static let maxModelHeight: CGFloat = 360
    static let horizontalInset: CGFloat = 6
    static let verticalInset: CGFloat = 8
    static let headerInset: CGFloat = 18
    // Headers bottom-align within their own rows; this spacing is the visual
    // inset before the selectable rows that follow.
    static let headerHeight: CGFloat = 18
    static let headerBottomSpacing: CGFloat = 4
    static let rowHeight: CGFloat = 32
    static let dividerSpacing: CGFloat = 7
    static let iconLeading: CGFloat = 12
    static let iconSlotSize: CGFloat = 16
    @MainActor static var iconPointSize: CGFloat { SidebarProjectRow.leadingIconFontSize }
    static let titleLeading: CGFloat = headerInset - horizontalInset
    static let titleTrailing: CGFloat = headerInset - horizontalInset
    static let trailingIconInset: CGFloat = 10
    static let trailingIconReservedWidth: CGFloat = 30

    @MainActor static var itemFont: NSFont { NSFont.preferredFont(forTextStyle: .body) }
    @MainActor static var truncatingParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }

    @MainActor
    static func mainContentSize(for configuration: ChatComposerActionRowView.ReasoningConfiguration) -> NSSize {
        let effortCount = configuration.selection.effortOptions.count
        let variableHeight: CGFloat
        if effortCount == 0 {
            variableHeight = 0
        } else {
            variableHeight = rowHeight * CGFloat(effortCount) +
                dividerSpacing + AppKitComposerPopoverDividerView.height + dividerSpacing
        }
        return NSSize(
            width: width,
            height: verticalInset * 2 + headerHeight + headerBottomSpacing + variableHeight + rowHeight
        )
    }

    @MainActor
    static func modelContentSize(
        groups: [ChatComposerActionRowView.ReasoningModelGroup],
        showsProviderHeaders: Bool
    ) -> NSSize {
        NSSize(
            width: modelWidth,
            height: min(maxModelHeight, modelDocumentHeight(groups: groups, showsProviderHeaders: showsProviderHeaders))
        )
    }

    @MainActor
    static func modelDocumentHeight(
        groups: [ChatComposerActionRowView.ReasoningModelGroup],
        showsProviderHeaders: Bool
    ) -> CGFloat {
        let modelCount = max(1, groups.flatMap(\.options).count)
        let headerCount = showsProviderHeaders ? groups.filter { $0.providerTitle != nil }.count : 0
        let dividerCount = showsProviderHeaders ? max(0, groups.count - 1) : 0
        return verticalInset * 2 +
            rowHeight * CGFloat(modelCount) +
            (headerHeight + headerBottomSpacing) * CGFloat(headerCount) +
            (AppKitComposerPopoverDividerView.height + dividerSpacing * 2) * CGFloat(dividerCount)
    }
}
