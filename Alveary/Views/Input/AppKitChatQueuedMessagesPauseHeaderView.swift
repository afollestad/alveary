import AppKit

@MainActor
final class AppKitChatQueuedMessagesPauseHeaderView: NSView {
    private let titleField = NSTextField(labelWithString: "")
    private let resumeButton = AppKitChatQueuedMessagesResumeButton(title: "Resume", target: nil, action: nil)
    private var onResume: () -> Void = {}
    private var actionTitle = "Resume"

    let measuredHeight: CGFloat = 44

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(title: String, actionTitle: String, onResume: @escaping () -> Void) {
        titleField.stringValue = title
        titleField.setAccessibilityLabel(title)
        self.actionTitle = actionTitle
        resumeButton.title = actionTitle
        resumeButton.setAccessibilityLabel(actionTitle)
        self.onResume = onResume
        updateAppearance()
        needsLayout = true
    }

    func updateAppearance() {
        titleField.textColor = appKitComposerPrimaryColor(in: self, opacity: 0.95)
        let actionAttributes: [NSAttributedString.Key: Any] = [
            .font: resumeButton.font ?? NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: appKitComposerSecondaryColor(in: self, opacity: 0.85)
        ]
        resumeButton.attributedTitle = NSAttributedString(string: actionTitle, attributes: actionAttributes)
        resumeButton.needsDisplay = true
    }

    override func layout() {
        super.layout()
        let titleLeading: CGFloat = 36
        let buttonSize = resumeButton.intrinsicContentSize
        let buttonWidth = ceil(buttonSize.width)
        let buttonHeight = ceil(buttonSize.height)
        let deleteControlTrailingX = bounds.width - AppKitChatQueuedMessagesLayout.rowTrailingPadding
        let buttonX = max(titleLeading, deleteControlTrailingX - buttonWidth)
        resumeButton.frame = NSRect(
            x: buttonX,
            y: floor((bounds.height - buttonHeight) / 2),
            width: buttonWidth,
            height: buttonHeight
        )

        let titleHeight = ceil(titleField.intrinsicContentSize.height)
        titleField.frame = NSRect(
            x: titleLeading,
            y: floor((bounds.height - titleHeight) / 2),
            width: max(0, buttonX - titleLeading - 16),
            height: titleHeight
        )
    }

    @objc private func handleResume() {
        onResume()
    }

    private func setup() {
        addSubview(titleField)
        addSubview(resumeButton)

        titleField.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1

        resumeButton.target = self
        resumeButton.action = #selector(handleResume)
        resumeButton.isBordered = false
        resumeButton.bezelStyle = .regularSquare
        resumeButton.font = .preferredFont(forTextStyle: .body)
        resumeButton.setButtonType(.momentaryChange)

        updateAppearance()
    }
}

private final class AppKitChatQueuedMessagesResumeButton: NSButton {
    private let verticalPadding: CGFloat = 6
    private var isPressed = false
    private var isHovering = false
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { isEnabled }
    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(
            width: ceil(size.width + AppKitChatQueuedMessagesLayout.pauseResumeButtonHorizontalPadding * 2),
            height: max(28, ceil(size.height + verticalPadding * 2))
        )
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        needsDisplay = true
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
        isHovering = false
        isPressed = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            return
        }
        window?.makeFirstResponder(self)
        isPressed = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else {
            return
        }
        let isInside = eventLocationIsInside(event)
        if isPressed != isInside {
            isPressed = isInside
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else {
            isPressed = false
            needsDisplay = true
            return
        }
        let shouldPerform = isPressed && eventLocationIsInside(event)
        isPressed = false
        needsDisplay = true
        if shouldPerform {
            performClick(nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled else {
            return
        }
        switch event.keyCode {
        case 36, 49:
            isPressed = true
            needsDisplay = true
            performClick(nil)
            isPressed = false
            needsDisplay = true
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else {
            return false
        }
        performClick(nil)
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
        drawBackground()
        super.draw(dirtyRect)
    }

    private func drawBackground() {
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: min(bounds.height / 2, 12),
            yRadius: min(bounds.height / 2, 12)
        )
        appKitComposerPrimaryColor(in: self, opacity: backgroundOpacity).setFill()
        path.fill()

        guard window?.firstResponder === self, isEnabled else {
            return
        }
        AppAccentFill.primaryNSColor.appKitResolvedColor(in: self, alpha: 0.24).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    private var backgroundOpacity: CGFloat {
        guard isEnabled else {
            return 0
        }
        if isHighlighted {
            return 0.18
        }
        if isPressed {
            return 0.18
        }
        if isHovering || window?.firstResponder === self {
            return 0.12
        }
        return 0
    }

    private func eventLocationIsInside(_ event: NSEvent) -> Bool {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            return true
        }
        guard window == nil else {
            return false
        }
        return bounds.contains(event.locationInWindow)
    }

    private func resetInteractionState() {
        isPressed = false
        isHovering = false
        needsDisplay = true
    }
}
