@preconcurrency import AppKit
import SwiftUI

struct AppImagePreviewWindowPresenter: NSViewRepresentable {
    let request: AppImagePreviewRequest?
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AppImagePreviewWindowAnchorView {
        let view = AppImagePreviewWindowAnchorView()
        view.onWindowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: AppImagePreviewWindowAnchorView, context: Context) {
        context.coordinator.request = request
        context.coordinator.onDismiss = onDismiss
        context.coordinator.attach(to: nsView.window)
        context.coordinator.sync()
    }

    static func dismantleNSView(_ nsView: AppImagePreviewWindowAnchorView, coordinator: Coordinator) {
        coordinator.dismissOverlay()
        coordinator.detachFromParentWindow()
    }

    @MainActor
    final class Coordinator {
        var request: AppImagePreviewRequest?
        var onDismiss: () -> Void = {}

        private weak var parentWindow: NSWindow?
        private var overlayWindow: AppImagePreviewOverlayPanel?
        private var overlayContentView: AppImagePreviewOverlayContentView?
        private var hostingView: NSHostingView<AnyView>?
        private var presentedRequest: AppImagePreviewRequest?
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
            guard let request else {
                dismissOverlay()
                return
            }
            guard let parentWindow else {
                return
            }
            if overlayWindow == nil {
                presentOverlay(for: request, parentWindow: parentWindow)
            } else if presentedRequest != request {
                updateOverlayRootView(for: request)
            }
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
            presentedRequest = nil
        }

        func detachFromParentWindow() {
            let center = NotificationCenter.default
            parentWindowObserverTokens.forEach { center.removeObserver($0) }
            parentWindowObserverTokens.removeAll()
            parentWindow = nil
        }

        private func presentOverlay(for request: AppImagePreviewRequest, parentWindow: NSWindow) {
            let overlayWindow = AppImagePreviewOverlayPanel(
                contentRect: parentWindow.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            overlayWindow.parentPreviewWindow = parentWindow
            overlayWindow.isOpaque = false
            overlayWindow.backgroundColor = .clear
            overlayWindow.hasShadow = false
            overlayWindow.animationBehavior = .none
            overlayWindow.collectionBehavior = [.fullScreenAuxiliary]

            let overlayContentView = AppImagePreviewOverlayContentView(frame: NSRect(origin: .zero, size: parentWindow.frame.size))
            overlayContentView.autoresizingMask = [.width, .height]

            let hostingView = NSHostingView(rootView: overlayContent(for: request))
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
            presentedRequest = request
            updateTrafficLightExclusionFrame()
        }

        private func updateOverlayRootView(for request: AppImagePreviewRequest) {
            hostingView?.rootView = overlayContent(for: request)
            presentedRequest = request
        }

        private func overlayContent(for request: AppImagePreviewRequest) -> AnyView {
            AnyView(
                AppImagePreviewOverlay(
                    request: request,
                    onDismiss: { [weak self] in
                        self?.onDismiss()
                    }
                )
            )
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

private final class AppImagePreviewOverlayContentView: NSView {
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

private final class AppImagePreviewOverlayPanel: NSPanel {
    weak var parentPreviewWindow: NSWindow?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func sendEvent(_ event: NSEvent) {
        if handleTrafficLightEvent(event) {
            return
        }
        super.sendEvent(event)
    }

    private func handleTrafficLightEvent(_ event: NSEvent) -> Bool {
        guard [.leftMouseDown, .leftMouseUp].contains(event.type),
              let parentPreviewWindow else {
            return false
        }

        let screenPoint = convertPoint(toScreen: event.locationInWindow)
        guard let targetButton = trafficLightButton(at: screenPoint, in: parentPreviewWindow) else {
            return false
        }

        if event.type == .leftMouseUp {
            parentPreviewWindow.makeKeyAndOrderFront(nil)
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

final class AppImagePreviewWindowAnchorView: NSView {
    var onWindowChanged: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChanged?(window)
    }
}
