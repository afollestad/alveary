import AppKit

@MainActor
final class ComposerReasoningFastToggleControl: ComposerReasoningMenuInteractiveControl {
    private static let symbolPointSize: CGFloat = 13
    private static let symbolNames = ["bolt", "bolt.fill"]
    private var onToggle: ((Bool) -> Void)?
    private var hasConfiguration = false
    private(set) var isOn = false
    override var intrinsicContentSize: NSSize {
        NSSize(width: 30, height: 30)
    }
    var opticalTrailingPadding: CGFloat {
        let widestSymbolWidth = Self.symbolNames.compactMap { symbolImage(named: $0)?.size.width }.max()
            ?? Self.symbolPointSize
        let symbolMaxX = floor(intrinsicContentSize.width / 2 - widestSymbolWidth / 2) + widestSymbolWidth
        return intrinsicContentSize.width - symbolMaxX
    }
    override var isHidden: Bool {
        didSet {
            setAccessibilityElement(!isHidden)
        }
    }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    func configure(isOn: Bool, isEnabled: Bool, onToggle: @escaping (Bool) -> Void) {
        self.onToggle = onToggle
        configureInteraction(isEnabled: isEnabled, disabledAlpha: 0.45)
        setOn(isOn, postsAccessibilityNotification: hasConfiguration)
        hasConfiguration = true
        needsDisplay = true
    }
    func setOn(_ isOn: Bool, postsAccessibilityNotification: Bool = true) {
        let didChange = self.isOn != isOn
        self.isOn = isOn
        updateAccessibility()
        if didChange, postsAccessibilityNotification {
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
        needsDisplay = true
    }
    override func performControlActivation() {
        toggle()
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let circleRect = centeredCircleRect
        let circlePath = NSBezierPath(ovalIn: circleRect)

        if let alpha = interactionBackgroundAlpha {
            NSColor.labelColor.appKitResolvedColor(in: self, alpha: alpha).setFill()
            circlePath.fill()
        }
        if showsFocusState, controlIsEnabled {
            AppAccentFill.primaryNSColor.appKitResolvedColor(in: self, alpha: 0.22).setStroke()
            circlePath.lineWidth = 1.5
            circlePath.stroke()
        }
        drawSymbol(in: circleRect)
    }
    #if DEBUG
    var debugSymbolName: String { symbolName }
    var debugSymbolTintColor: NSColor { symbolTintColor }
    var debugIsHovering: Bool { isHovering }
    var debugIsPressed: Bool { isPressed }
    var debugIsFocused: Bool { showsFocusState }
    var debugIsFirstResponder: Bool { window?.firstResponder === self }
    var debugShowsInteractionBackground: Bool { interactionBackgroundAlpha != nil }
    func performActivationForTesting() {
        toggle()
    }
    #endif
    private func setup() {
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        setAccessibilitySubrole(.switch)
        setAccessibilityLabel("Fast mode")
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        updateAccessibility()
    }
    private func updateAccessibility() {
        let helpText = isOn ? "Disable fast mode" : "Enable fast mode"
        toolTip = helpText
        setAccessibilityValue(isOn ? "On" : "Off")
        setAccessibilityHelp(helpText)
    }
    private func toggle() {
        guard controlIsEnabled else {
            return
        }
        let nextValue = !isOn
        setOn(nextValue)
        onToggle?(nextValue)
    }
    private var centeredCircleRect: NSRect {
        let diameter = min(bounds.width, bounds.height)
        return NSRect(
            x: floor((bounds.width - diameter) / 2),
            y: floor((bounds.height - diameter) / 2),
            width: diameter,
            height: diameter
        )
    }
    private var interactionBackgroundAlpha: CGFloat? {
        guard controlIsEnabled else {
            return nil
        }
        if isPressed {
            return 0.18
        }
        if isHovering || showsFocusState {
            return 0.13
        }
        return nil
    }
    private var symbolName: String {
        isOn ? "bolt.fill" : "bolt"
    }
    private var symbolTintColor: NSColor {
        let baseColor = isOn ? AppAccentIcon.foregroundNSColor : NSColor.labelColor
        let alpha: CGFloat = controlIsEnabled ? (isOn ? 1 : 0.80) : 0.35
        return baseColor.appKitResolvedColor(in: self, alpha: alpha)
    }
    private func drawSymbol(in circleRect: NSRect) {
        guard let image = symbolImage(named: symbolName) else {
            return
        }
        let imageRect = NSRect(
            x: floor(circleRect.midX - image.size.width / 2),
            y: floor(circleRect.midY - image.size.height / 2),
            width: image.size.width,
            height: image.size.height
        )
        image.draw(
            in: imageRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
    }
    private func symbolImage(named name: String) -> NSImage? {
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Self.symbolPointSize, weight: .bold)
            .applying(.init(hierarchicalColor: symbolTintColor))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfiguration)
    }
}
