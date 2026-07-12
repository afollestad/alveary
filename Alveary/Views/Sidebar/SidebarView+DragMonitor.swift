import AppKit
import SwiftUI

struct SidebarDragMonitor: NSViewRepresentable {
    let interactionState: SidebarDragInteractionState
    let onPointerMoved: @MainActor (CGPoint) -> Void
    let onAutoscroll: @MainActor () -> Void
    let onMouseUp: @MainActor (CGPoint) -> Void
    let onEscape: @MainActor () -> Void
    let onWindowInvalidated: @MainActor () -> Void

    func makeNSView(context: Context) -> SidebarDragMonitorView {
        let view = SidebarDragMonitorView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: SidebarDragMonitorView, context: Context) {
        update(nsView)
    }

    static func dismantleNSView(_ nsView: SidebarDragMonitorView, coordinator: ()) {
        nsView.dismantle()
    }

    private func update(_ view: SidebarDragMonitorView) {
        view.onPointerMoved = onPointerMoved
        view.onAutoscroll = onAutoscroll
        view.onMouseUp = onMouseUp
        view.onEscape = onEscape
        view.onWindowInvalidated = onWindowInvalidated
        view.updateInteractionState(interactionState)
    }
}

@MainActor
final class SidebarDragMonitorView: NSView {
    var onPointerMoved: ((CGPoint) -> Void)?
    var onAutoscroll: (() -> Void)?
    var onMouseUp: ((CGPoint) -> Void)?
    var onEscape: (() -> Void)?
    var onWindowInvalidated: (() -> Void)?

    private var interactionState = SidebarDragInteractionState.idle
    private var eventMonitor: Any?
    private var windowObservers: [NSObjectProtocol] = []
    private var autoscrollTimer: Timer?
    private var autoscrollSessionID: UUID?
    private var pointerLocation: CGPoint?
    private weak var monitoredScrollView: NSScrollView?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeEventMonitor()
            removeWindowObservers()
            stopAutoscroll()
            monitoredScrollView = nil
        } else {
            installEventMonitor()
            installWindowObservers()
            scheduleScrollViewRefresh()
        }
    }

    func updateInteractionState(_ state: SidebarDragInteractionState) {
        let previousSessionID = interactionState.activeSessionID
        interactionState = state
        switch state {
        case .active(let session):
            if previousSessionID != session.id {
                pointerLocation = currentPointerLocation()
            }
            updateAutoscroll()
        case .cancelledUntilMouseUp:
            pointerLocation = nil
            stopAutoscroll()
        case .idle:
            pointerLocation = nil
            stopAutoscroll()
        }
    }

    func dismantle() {
        interactionState = .idle
        removeEventMonitor()
        removeWindowObservers()
        stopAutoscroll()
        monitoredScrollView = nil
    }

    private func installEventMonitor() {
        guard eventMonitor == nil else {
            return
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handleEvent(event) ?? event
        }
    }

    private func removeEventMonitor() {
        guard let eventMonitor else {
            return
        }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        let action = sidebarDragMonitorAction(
            eventType: event.type,
            keyCode: event.type == .keyDown ? event.keyCode : 0,
            interactionState: interactionState,
            originatesInWindow: event.window === window
        )
        switch action {
        case .passThrough:
            return event
        case .pointerMoved:
            let location = convert(event.locationInWindow, from: nil)
            pointerLocation = location
            onPointerMoved?(location)
            updateAutoscroll()
            return event
        case .mouseUp:
            let location = convert(event.locationInWindow, from: nil)
            stopAutoscroll()
            onMouseUp?(location)
            return event
        case .escape:
            stopAutoscroll()
            onEscape?()
            return nil
        case .consumeKey:
            return nil
        }
    }

    private func installWindowObservers() {
        removeWindowObservers()
        guard let window else {
            return
        }

        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.invalidateForWindowChange()
                }
            })
        }
    }

    private func removeWindowObservers() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
    }

    private func invalidateForWindowChange() {
        guard interactionState != .idle else {
            return
        }
        interactionState = .idle
        pointerLocation = nil
        stopAutoscroll()
        onWindowInvalidated?()
    }

    private func updateAutoscroll() {
        guard let sessionID = sidebarAutoscrollSessionID(
            interactionState: interactionState,
            pointerLocation: pointerLocation,
            viewport: bounds
        ) else {
            stopAutoscroll()
            return
        }

        if autoscrollTimer != nil, autoscrollSessionID == sessionID {
            return
        }
        stopAutoscroll()
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performAutoscrollTick(sessionID: sessionID)
            }
        }
        autoscrollTimer = timer
        autoscrollSessionID = sessionID
        RunLoop.main.add(timer, forMode: .common)
    }

    private func currentPointerLocation() -> CGPoint? {
        guard let window else {
            return nil
        }
        return convert(window.mouseLocationOutsideOfEventStream, from: nil)
    }

    private func stopAutoscroll() {
        autoscrollTimer?.invalidate()
        autoscrollTimer = nil
        autoscrollSessionID = nil
    }

    private func performAutoscrollTick(sessionID: UUID) {
        guard sidebarAutoscrollTickOwnsTimer(
            tickSessionID: sessionID,
            timerSessionID: autoscrollSessionID
        ) else {
            return
        }
        guard case .active(let session) = interactionState,
              session.id == sessionID,
              let pointerLocation else {
            stopAutoscroll()
            return
        }

        let velocity = sidebarAutoscrollVelocity(location: pointerLocation, viewport: bounds)
        guard velocity != 0,
              let scrollView = monitoredScrollView ?? resolvedScrollView(),
              let documentView = scrollView.documentView else {
            stopAutoscroll()
            return
        }
        monitoredScrollView = scrollView

        let contentView = scrollView.contentView
        let clampedOriginY = sidebarAutoscrollOriginY(
            contentView: contentView,
            velocity: velocity,
            documentIsFlipped: documentView.isFlipped
        )

        guard abs(clampedOriginY - contentView.bounds.origin.y) > 0.01 else {
            stopAutoscroll()
            return
        }

        contentView.scroll(to: NSPoint(x: contentView.bounds.origin.x, y: clampedOriginY))
        scrollView.reflectScrolledClipView(contentView)
        // Preferences publish the moved row frames on the next SwiftUI layout pass;
        // recomputing now also keeps the target responsive on frames that stayed mounted.
        onAutoscroll?()
    }

    private func scheduleScrollViewRefresh() {
        DispatchQueue.main.async { [weak self] in
            self?.monitoredScrollView = self?.resolvedScrollView()
        }
    }

    private func resolvedScrollView() -> NSScrollView? {
        enclosingScrollView() ?? overlappingScrollView()
    }

    private func enclosingScrollView() -> NSScrollView? {
        var currentView: NSView? = self
        while let view = currentView {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            currentView = view.superview
        }
        return nil
    }

    private func overlappingScrollView() -> NSScrollView? {
        guard let contentView = window?.contentView else {
            return nil
        }
        let monitorRect = convert(bounds, to: nil)
        guard !monitorRect.isEmpty else {
            return nil
        }

        let monitorCenter = NSPoint(x: monitorRect.midX, y: monitorRect.midY)
        return contentView
            .sidebarDescendantScrollViews()
            .filter { scrollView in
                guard scrollView.documentView != nil else {
                    return false
                }
                let scrollRect = scrollView.convert(scrollView.bounds, to: nil)
                return scrollRect.contains(monitorCenter) || scrollRect.intersects(monitorRect)
            }
            .max { lhs, rhs in
                let lhsRect = lhs.convert(lhs.bounds, to: nil)
                let rhsRect = rhs.convert(rhs.bounds, to: nil)
                let lhsArea = lhsRect.intersection(monitorRect).sidebarArea
                let rhsArea = rhsRect.intersection(monitorRect).sidebarArea
                if lhsArea != rhsArea {
                    return lhsArea < rhsArea
                }
                return lhsRect.sidebarArea > rhsRect.sidebarArea
            }
    }
}

final class SidebarDragPointerRelay {
    var pendingMonitorLocation: CGPoint?
}

enum SidebarDragMonitorAction: Equatable {
    case passThrough
    case pointerMoved
    case mouseUp
    case escape
    case consumeKey
}

func sidebarDragMonitorAction(
    eventType: NSEvent.EventType,
    keyCode: UInt16,
    interactionState: SidebarDragInteractionState,
    originatesInWindow: Bool
) -> SidebarDragMonitorAction {
    guard originatesInWindow else {
        return .passThrough
    }

    switch eventType {
    case .keyDown:
        guard interactionState != .idle else {
            return .passThrough
        }
        if keyCode == SidebarDragKeyCode.escape {
            return interactionState.activeSessionID == nil ? .consumeKey : .escape
        }
        return SidebarDragKeyCode.suppressedDuringInteraction.contains(keyCode) ? .consumeKey : .passThrough
    case .leftMouseDragged:
        if case .cancelledUntilMouseUp = interactionState {
            return .passThrough
        }
        return .pointerMoved
    case .leftMouseUp:
        return .mouseUp
    default:
        return .passThrough
    }
}

func sidebarDragLocationInNamedSpace(
    monitorLocation: CGPoint,
    viewport: CGRect
) -> CGPoint {
    CGPoint(
        x: monitorLocation.x + viewport.minX,
        y: monitorLocation.y + viewport.minY
    )
}

func sidebarAutoscrollVelocity(
    location: CGPoint,
    viewport: CGRect,
    edgeBand: CGFloat = 32,
    maximumSpeed: CGFloat = 12
) -> CGFloat {
    guard edgeBand > 0,
          maximumSpeed > 0,
          location.x >= viewport.minX,
          location.x <= viewport.maxX,
          location.y >= viewport.minY,
          location.y <= viewport.maxY else {
        return 0
    }

    let distanceFromTop = location.y - viewport.minY
    if distanceFromTop < edgeBand {
        return -maximumSpeed * (1 - distanceFromTop / edgeBand)
    }

    let distanceFromBottom = viewport.maxY - location.y
    if distanceFromBottom < edgeBand {
        return maximumSpeed * (1 - distanceFromBottom / edgeBand)
    }

    return 0
}

func sidebarAutoscrollSessionID(
    interactionState: SidebarDragInteractionState,
    pointerLocation: CGPoint?,
    viewport: CGRect
) -> UUID? {
    guard case .active(let session) = interactionState,
          let pointerLocation,
          sidebarAutoscrollVelocity(location: pointerLocation, viewport: viewport) != 0 else {
        return nil
    }
    return session.id
}

@MainActor
func sidebarAutoscrollOriginY(
    contentView: NSClipView,
    velocity: CGFloat,
    documentIsFlipped: Bool
) -> CGFloat {
    let directionalVelocity = documentIsFlipped ? velocity : -velocity
    var proposedBounds = contentView.bounds
    proposedBounds.origin.y += directionalVelocity
    return contentView.constrainBoundsRect(proposedBounds).origin.y
}

func sidebarAutoscrollTickOwnsTimer(tickSessionID: UUID, timerSessionID: UUID?) -> Bool {
    tickSessionID == timerSessionID
}

private enum SidebarDragKeyCode {
    static let escape: UInt16 = 53
    static let suppressedDuringInteraction: Set<UInt16> = [
        36, // Return
        51, // Delete / Backspace
        76, // Keypad Enter
        117, // Forward Delete
        123, // Left Arrow
        124, // Right Arrow
        125, // Down Arrow
        126 // Up Arrow
    ]
}

private extension SidebarDragInteractionState {
    var activeSessionID: UUID? {
        guard case .active(let session) = self else {
            return nil
        }
        return session.id
    }
}

private extension NSView {
    func sidebarDescendantScrollViews() -> [NSScrollView] {
        var scrollViews: [NSScrollView] = []
        collectSidebarDescendantScrollViews(into: &scrollViews)
        return scrollViews
    }

    func collectSidebarDescendantScrollViews(into scrollViews: inout [NSScrollView]) {
        if let scrollView = self as? NSScrollView {
            scrollViews.append(scrollView)
        }
        for subview in subviews {
            subview.collectSidebarDescendantScrollViews(into: &scrollViews)
        }
    }
}

private extension NSRect {
    var sidebarArea: CGFloat {
        guard !isEmpty else {
            return 0
        }
        return width * height
    }
}
