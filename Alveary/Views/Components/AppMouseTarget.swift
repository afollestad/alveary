import AppKit
import SwiftUI

/// Mouse target for compact controls that sit beside selectable or animated
/// content. AppKit owns the actual mouse hit after SwiftUI lays out the tiny
/// overlay, while the surrounding SwiftUI `Button` remains in place for keyboard
/// and accessibility activation.
struct AppMouseTarget: NSViewRepresentable {
    let activation: AppMouseActivationCoordinator
    let action: () -> Void
    let pressedChanged: (Bool) -> Void

    init(
        activation: AppMouseActivationCoordinator,
        action: @escaping () -> Void,
        pressedChanged: @escaping (Bool) -> Void
    ) {
        self.activation = activation
        self.action = action
        self.pressedChanged = pressedChanged
    }

    func makeNSView(context: Context) -> AppMouseTargetView {
        let view = AppMouseTargetView()
        view.activation = activation
        view.action = action
        view.pressedChanged = pressedChanged
        return view
    }

    func updateNSView(_ nsView: AppMouseTargetView, context: Context) {
        nsView.activation = activation
        nsView.action = action
        nsView.pressedChanged = pressedChanged
    }

    static func dismantleNSView(_ nsView: AppMouseTargetView, coordinator: ()) {
        nsView.dismantle()
    }
}

final class AppMouseTargetView: NSView {
    var activation: AppMouseActivationCoordinator?
    var action: (() -> Void)?
    var pressedChanged: ((Bool) -> Void)?
    private var eventMonitor: Any?
    private var trackedActivationCount: Int?
    private var isTrackingClick = false
    private var isPressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeEventMonitor()
            resetPressedState()
        } else {
            installEventMonitor()
        }
    }

    override func mouseDown(with event: NSEvent) {
        setPressed(true)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        setPressed(bounds.contains(point))
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let shouldTriggerAction = bounds.contains(point)
        setPressed(false)
        if shouldTriggerAction {
            action?()
        }
    }

    func dismantle() {
        removeEventMonitor()
        resetPressedState()
    }

    func resetPressedState() {
        setPressed(false)
    }

    private func installEventMonitor() {
        guard eventMonitor == nil else {
            return
        }
        // SwiftUI/AppKit can leave stale mouse-hit regions after animated lazy-list
        // height changes. The monitor does not replace the Button; it watches
        // this target's current AppKit bounds and only falls back if normal
        // activation did not mark the shared coordinator.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handleMonitoredEvent(event) ?? event
        }
    }

    private func removeEventMonitor() {
        guard let eventMonitor else {
            return
        }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
        isTrackingClick = false
    }

    private func handleMonitoredEvent(_ event: NSEvent) -> NSEvent? {
        guard event.window === window else {
            return event
        }

        let point = convert(event.locationInWindow, from: nil)
        let isInside = bounds.contains(point)
        switch event.type {
        case .leftMouseDown:
            guard isInside else {
                return event
            }
            isTrackingClick = true
            trackedActivationCount = activation?.activationCount
            setPressed(true)
            // Let SwiftUI still receive the event; this monitor is only a fallback.
            return event
        case .leftMouseDragged:
            guard isTrackingClick else {
                return event
            }
            setPressed(isInside)
            return event
        case .leftMouseUp:
            guard isTrackingClick else {
                return event
            }
            let activationCount = trackedActivationCount
            isTrackingClick = false
            trackedActivationCount = nil
            setPressed(false)
            if isInside {
                scheduleFallbackActivation(startingActivationCount: activationCount)
            }
            return event
        default:
            return event
        }
    }

    private func scheduleFallbackActivation(startingActivationCount: Int?) {
        // By the time this fires, the Button has had a chance to mark activation
        // during normal event delivery. Matching counts mean it never did.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self,
                  let activation,
                  activation.activationCount == startingActivationCount else {
                return
            }
            action?()
        }
    }

    private func setPressed(_ newValue: Bool) {
        guard isPressed != newValue else {
            return
        }
        isPressed = newValue
        pressedChanged?(newValue)
    }
}

final class AppMouseActivationCoordinator {
    private(set) var activationCount = 0

    func markActivation() {
        activationCount += 1
    }
}
