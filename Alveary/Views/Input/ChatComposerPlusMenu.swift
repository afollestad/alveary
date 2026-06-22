import AppKit

@MainActor
final class ComposerPlusButton: NSView {
    var actionHandler: (() -> Void)?

    private var controlIsEnabled = true
    private var controlHeight = ChatComposerActionRowView.defaultHeight
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
        NSSize(width: controlHeight, height: controlHeight)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(height: CGFloat, isEnabled: Bool, actionHandler: @escaping () -> Void) {
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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let diameter = min(bounds.width, bounds.height)
        let circleRect = NSRect(
            x: floor((bounds.width - diameter) / 2),
            y: floor((bounds.height - diameter) / 2),
            width: diameter,
            height: diameter
        )
        let circlePath = NSBezierPath(ovalIn: circleRect)
        NSGraphicsContext.current?.saveGraphicsState()
        circlePath.setClip()
        NSColor.labelColor.appKitResolvedColor(in: self, alpha: backgroundAlpha).setFill()
        circlePath.fill()
        if window?.firstResponder === self, controlIsEnabled {
            AppAccentFill.primaryNSColor.appKitResolvedColor(in: self, alpha: 0.22).setStroke()
            circlePath.lineWidth = 1.5
            circlePath.stroke()
        }
        drawPlus(in: circleRect)
        NSGraphicsContext.current?.restoreGraphicsState()
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

    private func setup() {
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Open composer actions")
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func drawPlus(in rect: NSRect) {
        let alpha: CGFloat = controlIsEnabled ? 0.72 : 0.24
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let halfLength = min(rect.width, rect.height) * 0.24
        let plusPath = NSBezierPath()
        plusPath.move(to: NSPoint(x: center.x - halfLength, y: center.y))
        plusPath.line(to: NSPoint(x: center.x + halfLength, y: center.y))
        plusPath.move(to: NSPoint(x: center.x, y: center.y - halfLength))
        plusPath.line(to: NSPoint(x: center.x, y: center.y + halfLength))
        plusPath.lineWidth = 2
        plusPath.lineCapStyle = .round
        NSColor.labelColor.appKitResolvedColor(in: self, alpha: alpha).setStroke()
        plusPath.stroke()
    }

    private func resetInteractionState() {
        isPressed = false
        isHovering = false
        needsDisplay = true
    }
}

@MainActor
final class ComposerPlusMenuViewController: NSViewController {
    struct Configuration {
        let isGoalModeArmed: Bool
        let isGoalModeToggleEnabled: Bool
        let goalModeDisabledTooltip: String?
        let isPlanModeEnabled: Bool
        let isPlanModeToggleEnabled: Bool
        let planModeDisabledTooltip: String?
        let onAddPhotosAndFiles: () -> Void
        let onPlanModeChange: (Bool) -> Void
        let onGoalModeChange: (Bool) -> Void
    }

    private let configuration: Configuration

    init(configuration: Configuration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = ComposerPlusMenuMetrics.contentSize
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = ComposerPlusMenuView(configuration: configuration)
    }
}

@MainActor
private final class ComposerPlusMenuView: AppKitComposerPopoverSurfaceView {
    private let configuration: ComposerPlusMenuViewController.Configuration
    private let addFilesRow = ComposerPlusMenuRowView()
    private let goalSwitch = NSSwitch()
    private let goalRow = ComposerPlusMenuRowView()
    private let planSwitch = NSSwitch()
    private let planRow = ComposerPlusMenuRowView()
    private let divider = AppKitComposerPopoverDividerView()

    init(configuration: ComposerPlusMenuViewController.Configuration) {
        self.configuration = configuration
        super.init(frame: NSRect(origin: .zero, size: ComposerPlusMenuMetrics.contentSize))
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        addFilesRow.frame = NSRect(
            x: ComposerPlusMenuMetrics.horizontalInset,
            y: ComposerPlusMenuMetrics.verticalInset,
            width: bounds.width - ComposerPlusMenuMetrics.horizontalInset * 2,
            height: ComposerPlusMenuMetrics.rowHeight
        )
        divider.frame = NSRect(
            x: AppKitComposerPopoverDividerView.horizontalInset,
            y: ComposerPlusMenuMetrics.verticalInset + ComposerPlusMenuMetrics.rowHeight + ComposerPlusMenuMetrics.dividerSpacing,
            width: bounds.width - AppKitComposerPopoverDividerView.horizontalInset * 2,
            height: AppKitComposerPopoverDividerView.height
        )
        goalRow.frame = NSRect(
            x: ComposerPlusMenuMetrics.horizontalInset,
            y: divider.frame.maxY + ComposerPlusMenuMetrics.dividerSpacing,
            width: bounds.width - ComposerPlusMenuMetrics.horizontalInset * 2,
            height: ComposerPlusMenuMetrics.rowHeight
        )
        planRow.frame = NSRect(
            x: ComposerPlusMenuMetrics.horizontalInset,
            y: goalRow.frame.maxY + ComposerPlusMenuMetrics.dividerSpacing,
            width: bounds.width - ComposerPlusMenuMetrics.horizontalInset * 2,
            height: ComposerPlusMenuMetrics.rowHeight
        )
    }

    private func setup() {
        setupAddFilesButton()
        setupDivider()
        setupGoalRow()
        setupPlanRow()
    }

    private func setupAddFilesButton() {
        addSubview(addFilesRow)
        addFilesRow.configure(.init(
            title: "Add photos & files",
            icon: symbolImage(named: "paperclip", pointSize: ComposerPlusMenuMetrics.iconPointSize),
            accessibilityLabel: "Add photos and files",
            isEnabled: true,
            toolTip: nil,
            trailingView: nil,
            action: { [weak self] in
                self?.configuration.onAddPhotosAndFiles()
            }
        ))
    }

    private func setupDivider() {
        addSubview(divider)
    }

    private func setupPlanRow() {
        planRow.toolTip = configuration.planModeDisabledTooltip
        addSubview(planRow)

        planSwitch.translatesAutoresizingMaskIntoConstraints = false
        planSwitch.controlSize = .small
        planSwitch.state = configuration.isPlanModeEnabled ? .on : .off
        planSwitch.isEnabled = configuration.isPlanModeToggleEnabled
        planSwitch.toolTip = configuration.planModeDisabledTooltip
        planSwitch.target = self
        planSwitch.action = #selector(planSwitchChanged)
        planSwitch.setAccessibilityLabel("Plan mode")
        planSwitch.setAccessibilityValue(configuration.isPlanModeEnabled ? "On" : "Off")
        planRow.configure(.init(
            title: "Plan mode",
            icon: symbolImage(named: "checklist", pointSize: ComposerPlusMenuMetrics.iconPointSize),
            accessibilityLabel: "Toggle plan mode",
            isEnabled: configuration.isPlanModeToggleEnabled,
            toolTip: configuration.planModeDisabledTooltip,
            trailingView: planSwitch,
            action: { [weak self] in
                self?.togglePlanMode()
            }
        ))
    }

    private func setupGoalRow() {
        goalRow.toolTip = configuration.goalModeDisabledTooltip
        addSubview(goalRow)

        goalSwitch.translatesAutoresizingMaskIntoConstraints = false
        goalSwitch.controlSize = .small
        goalSwitch.state = configuration.isGoalModeArmed ? .on : .off
        goalSwitch.isEnabled = configuration.isGoalModeToggleEnabled
        goalSwitch.toolTip = configuration.goalModeDisabledTooltip
        goalSwitch.target = self
        goalSwitch.action = #selector(goalSwitchChanged)
        goalSwitch.setAccessibilityLabel("Goal mode")
        goalSwitch.setAccessibilityValue(configuration.isGoalModeArmed ? "On" : "Off")
        goalRow.configure(.init(
            title: "Goal mode",
            icon: symbolImage(named: "target", pointSize: ComposerPlusMenuMetrics.iconPointSize),
            accessibilityLabel: "Toggle goal mode",
            isEnabled: configuration.isGoalModeToggleEnabled,
            toolTip: configuration.goalModeDisabledTooltip,
            trailingView: goalSwitch,
            action: { [weak self] in
                self?.toggleGoalMode()
            }
        ))
    }

    @objc private func goalSwitchChanged() {
        configuration.onGoalModeChange(goalSwitch.state == .on)
    }

    @objc private func planSwitchChanged() {
        configuration.onPlanModeChange(planSwitch.state == .on)
    }

    private func toggleGoalMode() {
        guard configuration.isGoalModeToggleEnabled else {
            return
        }
        let isEnabled = goalSwitch.state != .on
        goalSwitch.state = isEnabled ? .on : .off
        goalSwitch.setAccessibilityValue(isEnabled ? "On" : "Off")
        configuration.onGoalModeChange(isEnabled)
    }

    private func togglePlanMode() {
        guard configuration.isPlanModeToggleEnabled else {
            return
        }
        let isEnabled = planSwitch.state != .on
        planSwitch.state = isEnabled ? .on : .off
        planSwitch.setAccessibilityValue(isEnabled ? "On" : "Off")
        configuration.onPlanModeChange(isEnabled)
    }

    private func symbolImage(named name: String, pointSize: CGFloat) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }
}
