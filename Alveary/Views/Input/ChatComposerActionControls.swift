import AppKit

/// Native AppKit menu button that mirrors SwiftUI `.menu` picker visuals while
/// keeping deterministic intrinsic sizing for the migrated composer action row.
final class ComposerMenuButton: NSView {
    private var options: [ChatComposerActionRowView.MenuOption] = []
    private var selectedValue: String = ""
    private var title: String = ""
    private var menuHeaderTitle: String?
    private var onSelect: ((String) -> Void)?
    private var controlIsEnabled = true
    private var isPressed = false
    private var isHovering = false
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override var acceptsFirstResponder: Bool { false }

    override var isHidden: Bool {
        didSet {
            if isHidden {
                resetInteractionState()
            }
        }
    }

    override var intrinsicContentSize: NSSize {
        let font = NSFont.preferredFont(forTextStyle: .body)
        let widestTitle = ([title] + options.map(\.title))
            .map { ceil($0.size(withAttributes: [.font: font]).width) }
            .max() ?? 0
        let width = widestTitle + 48
        // SwiftUI's `.menu` picker is shorter than the 30pt action row.
        // Keep that visual height and let the native row center it vertically.
        return NSSize(width: max(88, width), height: 24)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.popUpButton)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(true)
        setAccessibilityRole(.popUpButton)
    }

    func configure(
        title: String,
        options: [ChatComposerActionRowView.MenuOption],
        selectedValue: String,
        isEnabled: Bool,
        onSelect: @escaping (String) -> Void
    ) {
        self.title = title
        self.options = options
        self.selectedValue = selectedValue
        self.onSelect = onSelect
        controlIsEnabled = isEnabled
        if !isEnabled {
            resetInteractionState()
        }
        alphaValue = 1
        setAccessibilityEnabled(isEnabled)
        setAccessibilityValue(title)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    func setMenuHeaderTitle(_ menuHeaderTitle: String?) {
        self.menuHeaderTitle = menuHeaderTitle
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
        needsDisplay = true
        NSMenu.popUpContextMenu(menu(), with: event, for: self)
        isPressed = false
        needsDisplay = true
    }

    override func accessibilityPerformPress() -> Bool {
        guard controlIsEnabled else {
            return false
        }
        _ = menu().popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY), in: self)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.labelColor.appKitResolvedColor(in: self, alpha: fillAlpha).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()

        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.labelColor.appKitResolvedColor(in: self, alpha: textAlpha)
        ]
        let titleSize = title.size(withAttributes: textAttributes)
        let textRect = NSRect(
            x: 12,
            y: floor((bounds.height - titleSize.height) / 2),
            width: max(0, bounds.width - 38),
            height: titleSize.height
        )
        (title as NSString).draw(in: textRect, withAttributes: textAttributes)

        if let image = symbolImage(
            named: "chevron.up.chevron.down",
            pointSize: 12,
            color: NSColor.labelColor.appKitResolvedColor(in: self, alpha: chevronAlpha)
        ) {
            let imageRect = NSRect(x: bounds.maxX - 24, y: floor((bounds.height - 14) / 2), width: 12, height: 14)
            image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    private var fillAlpha: CGFloat {
        if !controlIsEnabled {
            return 0.04
        }
        if isPressed {
            return 0.16
        }
        return isHovering ? 0.12 : 0.08
    }

    private var textAlpha: CGFloat {
        controlIsEnabled ? 0.85 : 0.26
    }

    private var chevronAlpha: CGFloat {
        guard controlIsEnabled else {
            return 0.16
        }
        return isDarkAppearance ? 0.63 : 0.69
    }

    private var isDarkAppearance: Bool {
        appKitRenderingAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()
        if let menuHeaderTitle {
            let header = NSMenuItem(title: menuHeaderTitle, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
        }
        for option in options {
            let item = NSMenuItem(title: option.title, action: #selector(selectMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.value
            item.state = option.value == selectedValue ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func symbolImage(named name: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(.init(hierarchicalColor: color))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    @objc private func selectMenuItem(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else {
            return
        }
        onSelect?(value)
    }

    private func resetInteractionState() {
        isPressed = false
        isHovering = false
        needsDisplay = true
    }
}

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
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        if isHovering, controlIsEnabled, !isPressed {
            foregroundColor.appKitResolvedColor(in: self, alpha: 0.06 * pressedBodyOpacity).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
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
