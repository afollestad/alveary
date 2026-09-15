@preconcurrency import AppKit
import SwiftUI

/// Identifies the main scene's actual window without confusing retained closed windows or
/// auxiliary panels with an open main scene.
struct MainWindowRegistration: NSViewRepresentable {
    let presenter: MainWindowPresenter

    func makeNSView(context: Context) -> MainWindowRegistrationAnchorView {
        MainWindowRegistrationAnchorView(presenter: presenter)
    }

    func updateNSView(_ nsView: MainWindowRegistrationAnchorView, context: Context) {}

    static func dismantleNSView(_ nsView: MainWindowRegistrationAnchorView, coordinator: ()) {
        nsView.detach()
    }
}

/// Closing may leave this view attached, so presentation lifetime follows window notifications
/// as well as view attachment. Reopening a retained scene does not need a new view hierarchy.
final class MainWindowRegistrationAnchorView: NSView {
    private let presenter: MainWindowPresenter
    private weak var observedWindow: NSWindow?

    init(presenter: MainWindowPresenter) {
        self.presenter = presenter
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard observedWindow !== window else {
            return
        }

        detach()
        guard let window else {
            return
        }

        observedWindow = window
        presenter.register(window: window)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: window)
        center.addObserver(self, selector: #selector(windowDidBecomeKey(_:)), name: NSWindow.didBecomeKeyNotification, object: window)
    }

    /// Dismantling and window detachment can race with a replacement scene's registration.
    func detach() {
        if let observedWindow {
            let center = NotificationCenter.default
            center.removeObserver(self, name: NSWindow.willCloseNotification, object: observedWindow)
            center.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: observedWindow)
            presenter.unregister(window: observedWindow)
        }
        observedWindow = nil
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }
        presenter.unregister(window: window)
    }

    /// SwiftUI can reopen a retained window without moving its existing view hierarchy again.
    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }
        presenter.register(window: window)
    }
}
