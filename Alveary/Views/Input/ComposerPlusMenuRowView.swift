import AppKit

@MainActor
final class ComposerPlusMenuRowView: NSView {
    struct Configuration {
        let title: String
        let icon: NSImage?
        let accessibilityLabel: String
        let isEnabled: Bool
        let toolTip: String?
        let trailingView: NSView?
        let action: () -> Void
    }

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var trailingView: NSView?
    private var action: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var isPressed = false
    private var controlIsEnabled = true

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { controlIsEnabled }
    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(_ configuration: Configuration) {
        label.stringValue = configuration.title
        iconView.image = configuration.icon
        toolTip = configuration.toolTip
        controlIsEnabled = configuration.isEnabled
        action = configuration.action
        alphaValue = configuration.isEnabled ? 1 : 0.55
        setAccessibilityLabel(configuration.accessibilityLabel)
        setAccessibilityEnabled(configuration.isEnabled)
        installTrailingView(configuration.trailingView)
        if !configuration.isEnabled {
            resetInteractionState()
        }
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseEntered(with event: NSEvent) {
        guard controlIsEnabled else {
            return
        }
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
        action?()
    }

    override func keyDown(with event: NSEvent) {
        guard controlIsEnabled else {
            return
        }
        switch event.keyCode {
        case 36, 49:
            action?()
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard controlIsEnabled else {
            return false
        }
        action?()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard controlIsEnabled else {
            return
        }
        let alpha: CGFloat
        if isPressed {
            alpha = 0.14
        } else if isHovering {
            alpha = 0.09
        } else {
            return
        }
        NSColor.labelColor.appKitResolvedColor(in: self, alpha: alpha).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 7, yRadius: 7).fill()
    }

    private func setup() {
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        label.font = ComposerPlusMenuMetrics.itemFont
        label.textColor = .labelColor
        label.setAccessibilityElement(false)
        iconView.contentTintColor = .labelColor
        iconView.setAccessibilityElement(false)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        addSubview(label)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ComposerPlusMenuMetrics.iconLeading),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: ComposerPlusMenuMetrics.iconSlotSize),
            iconView.heightAnchor.constraint(equalToConstant: ComposerPlusMenuMetrics.iconSlotSize),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: ComposerPlusMenuMetrics.labelSpacing),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func installTrailingView(_ view: NSView?) {
        guard trailingView !== view else {
            return
        }
        trailingView?.removeFromSuperview()
        trailingView = view
        guard let view else {
            return
        }
        addSubview(view)
        NSLayoutConstraint.activate([
            view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ComposerPlusMenuMetrics.trailingInset),
            view.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.leadingAnchor, constant: -ComposerPlusMenuMetrics.trailingSpacing)
        ])
    }

    private func resetInteractionState() {
        isHovering = false
        isPressed = false
        needsDisplay = true
    }
}

enum ComposerPlusMenuMetrics {
    static let contentSize = NSSize(width: 244, height: 84)
    static let horizontalInset: CGFloat = 6
    static let verticalInset: CGFloat = 6
    static let rowHeight: CGFloat = 32
    static let dividerSpacing: CGFloat = 4
    static let iconLeading: CGFloat = 12
    @MainActor static var iconSlotSize: CGFloat { SidebarProjectRow.leadingIconWidth }
    @MainActor static var iconPointSize: CGFloat { SidebarProjectRow.leadingIconFontSize }
    static let labelSpacing: CGFloat = 10
    static let trailingInset: CGFloat = 10
    static let trailingSpacing: CGFloat = 8
    @MainActor static var itemFont: NSFont { NSFont.preferredFont(forTextStyle: .body) }
}
