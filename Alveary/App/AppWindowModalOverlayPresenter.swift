@preconcurrency import AppKit
import SwiftUI

struct AppWindowModalOverlayPresenter: NSViewRepresentable {
    enum DismissPolicy {
        case dismissible
        case nonDismissible
    }

    struct Modal {
        let id: String
        let dismissPolicy: DismissPolicy
        let content: AnyView

        init(
            id: String,
            dismissPolicy: DismissPolicy = .dismissible,
            content: AnyView
        ) {
            self.id = id
            self.dismissPolicy = dismissPolicy
            self.content = content
        }
    }

    let modal: Modal?
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AppWindowModalOverlayAnchorView {
        let view = AppWindowModalOverlayAnchorView()
        view.onWindowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: AppWindowModalOverlayAnchorView, context: Context) {
        context.coordinator.modal = modal
        context.coordinator.onDismiss = onDismiss
        context.coordinator.attach(to: nsView.window)
        context.coordinator.sync()
    }

    static func dismantleNSView(_ nsView: AppWindowModalOverlayAnchorView, coordinator: Coordinator) {
        coordinator.dismissOverlay()
        coordinator.detachFromParentWindow()
    }

    @MainActor
    final class Coordinator {
        var modal: Modal?
        var onDismiss: () -> Void = {}

        private weak var parentWindow: NSWindow?
        private var overlayWindow: AppWindowModalOverlayPanel?
        private var overlayContentView: AppWindowModalOverlayContentView?
        private var hostingView: NSHostingView<AnyView>?
        private var presentedModalID: String?
        private var parentWindowObserverTokens: [NSObjectProtocol] = []

        func attach(to window: NSWindow?) {
            guard parentWindow !== window else {
                return
            }
            dismissOverlay()
            detachFromParentWindow()
            parentWindow = window
            if let window {
                observeParentWindow(window)
            }
            sync()
        }

        func sync() {
            guard let modal else {
                dismissOverlay()
                return
            }
            guard let parentWindow else {
                return
            }
            if overlayWindow == nil {
                presentOverlay(modal, parentWindow: parentWindow)
            } else if presentedModalID != modal.id {
                updateOverlayRootView(modal)
            }
            overlayWindow?.dismissPolicy = modal.dismissPolicy
            updateOverlayFrame()
        }

        func dismissOverlay() {
            if let parentWindow,
               let overlayWindow {
                parentWindow.removeChildWindow(overlayWindow)
            }
            overlayWindow?.orderOut(nil)
            overlayWindow?.close()
            overlayWindow = nil
            overlayContentView = nil
            hostingView = nil
            presentedModalID = nil
        }

        func detachFromParentWindow() {
            let center = NotificationCenter.default
            parentWindowObserverTokens.forEach { center.removeObserver($0) }
            parentWindowObserverTokens.removeAll()
            parentWindow = nil
        }

        private func presentOverlay(_ modal: Modal, parentWindow: NSWindow) {
            let overlayWindow = AppWindowModalOverlayPanel(
                contentRect: parentWindow.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            overlayWindow.parentModalWindow = parentWindow
            overlayWindow.dismissPolicy = modal.dismissPolicy
            overlayWindow.onDismiss = { [weak self] in
                self?.onDismiss()
            }
            overlayWindow.isOpaque = false
            overlayWindow.backgroundColor = .clear
            overlayWindow.hasShadow = false
            overlayWindow.animationBehavior = .none
            overlayWindow.collectionBehavior = [.fullScreenAuxiliary]

            let overlayContentView = AppWindowModalOverlayContentView(frame: NSRect(origin: .zero, size: parentWindow.frame.size))
            overlayContentView.autoresizingMask = [.width, .height]

            let hostingView = NSHostingView(rootView: modal.content)
            hostingView.frame = overlayContentView.bounds
            hostingView.autoresizingMask = [.width, .height]
            overlayContentView.addSubview(hostingView)

            overlayWindow.contentView = overlayContentView
            overlayWindow.setFrame(parentWindow.frame, display: false)
            parentWindow.addChildWindow(overlayWindow, ordered: .above)
            overlayWindow.makeKeyAndOrderFront(nil)

            self.overlayWindow = overlayWindow
            self.overlayContentView = overlayContentView
            self.hostingView = hostingView
            presentedModalID = modal.id
            updateTrafficLightExclusionFrame()
        }

        private func updateOverlayRootView(_ modal: Modal) {
            guard let overlayContentView else {
                return
            }
            replaceHostingView(with: modal, in: overlayContentView)
        }

        func replaceHostingView(
            with modal: Modal,
            in overlayContentView: AppWindowModalOverlayContentView
        ) {
            hostingView?.removeFromSuperview()
            let hostingView = NSHostingView(rootView: modal.content)
            hostingView.frame = overlayContentView.bounds
            hostingView.autoresizingMask = [.width, .height]
            overlayContentView.addSubview(hostingView)
            self.hostingView = hostingView
            presentedModalID = modal.id
        }

        private func observeParentWindow(_ parentWindow: NSWindow) {
            let center = NotificationCenter.default
            let notifications: [NSNotification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.didMoveNotification,
                NSWindow.didChangeScreenNotification,
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification
            ]
            parentWindowObserverTokens = notifications.map { name in
                center.addObserver(forName: name, object: parentWindow, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.updateOverlayFrame()
                    }
                }
            }
            parentWindowObserverTokens.append(
                center.addObserver(forName: NSWindow.willCloseNotification, object: parentWindow, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.dismissOverlay()
                        self?.detachFromParentWindow()
                    }
                }
            )
        }

        private func updateOverlayFrame() {
            guard let parentWindow,
                  let overlayWindow,
                  let overlayContentView else {
                return
            }
            overlayWindow.setFrame(parentWindow.frame, display: false)
            overlayContentView.frame = NSRect(origin: .zero, size: parentWindow.frame.size)
            updateTrafficLightExclusionFrame()
        }

        private func updateTrafficLightExclusionFrame() {
            guard let parentWindow,
                  let overlayWindow,
                  let overlayContentView else {
                return
            }
            let buttons = [
                parentWindow.standardWindowButton(.closeButton),
                parentWindow.standardWindowButton(.miniaturizeButton),
                parentWindow.standardWindowButton(.zoomButton)
            ].compactMap { $0 }
            let trafficLightScreenFrames = buttons
                .filter { !$0.isHidden && $0.window != nil }
                .map { button in
                    let frameInWindow = button.convert(button.bounds, to: nil)
                    return parentWindow.convertToScreen(frameInWindow)
                }

            overlayContentView.windowCornerRadius = parentWindow.styleMask.contains(.fullScreen) ? 0 : 12
            overlayContentView.trafficLightCutoutFrames = trafficLightScreenFrames
                .map { screenFrame in
                    overlayWindow.convertFromScreen(screenFrame)
                }
        }
    }
}

final class AppWindowModalOverlayContentView: NSView {
    var windowCornerRadius: CGFloat = 12 {
        didSet {
            updateMask()
        }
    }

    var trafficLightCutoutFrames: [NSRect] = [] {
        didSet {
            updateMask()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateMask()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !trafficLightCutoutFrames.contains(where: { $0.contains(point) }) else {
            return nil
        }
        return super.hitTest(point)
    }

    private func updateMask() {
        let path = CGMutablePath()
        if windowCornerRadius > 0 {
            path.addRoundedRect(in: bounds, cornerWidth: windowCornerRadius, cornerHeight: windowCornerRadius)
        } else {
            path.addRect(bounds)
        }
        trafficLightCutoutFrames.forEach { cutoutFrame in
            guard !cutoutFrame.isEmpty else {
                return
            }
            path.addEllipse(in: cutoutFrame)
        }

        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.path = path
        mask.fillRule = .evenOdd
        layer?.mask = mask
    }
}

final class AppWindowModalOverlayPanel: NSPanel {
    weak var parentModalWindow: NSWindow?
    var onDismiss: (() -> Void)?
    var dismissPolicy = AppWindowModalOverlayPresenter.DismissPolicy.dismissible

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
        setAccessibilityModal(true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func cancelOperation(_ sender: Any?) {
        guard dismissPolicy == .dismissible else {
            return
        }
        onDismiss?()
    }

    override func performClose(_ sender: Any?) {
        guard dismissPolicy == .dismissible else {
            return
        }
        onDismiss?()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           event.keyCode == 53 {
            guard dismissPolicy == .dismissible else {
                return
            }
            onDismiss?()
            return
        }
        if handleTrafficLightEvent(event) {
            return
        }
        super.sendEvent(event)
    }

    private func handleTrafficLightEvent(_ event: NSEvent) -> Bool {
        guard [.leftMouseDown, .leftMouseUp].contains(event.type),
              let parentModalWindow else {
            return false
        }

        let screenPoint = convertPoint(toScreen: event.locationInWindow)
        guard let targetButton = trafficLightButton(at: screenPoint, in: parentModalWindow) else {
            return false
        }

        guard dismissPolicy == .dismissible else {
            return true
        }

        if event.type == .leftMouseUp {
            parentModalWindow.makeKeyAndOrderFront(nil)
            targetButton.performClick(nil)
        }
        return true
    }

    private func trafficLightButton(at screenPoint: NSPoint, in parentWindow: NSWindow) -> NSButton? {
        let buttons = [
            parentWindow.standardWindowButton(.closeButton),
            parentWindow.standardWindowButton(.miniaturizeButton),
            parentWindow.standardWindowButton(.zoomButton)
        ].compactMap { $0 }

        for button in buttons where !button.isHidden && button.window != nil {
            let frameInWindow = button.convert(button.bounds, to: nil)
            let screenFrame = parentWindow.convertToScreen(frameInWindow)
            if screenFrame.contains(screenPoint) {
                return button
            }
        }
        return nil
    }
}

final class AppWindowModalOverlayAnchorView: NSView {
    var onWindowChanged: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChanged?(window)
    }
}
