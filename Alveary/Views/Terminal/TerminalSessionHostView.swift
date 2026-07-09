@preconcurrency import AppKit
import SwiftUI

struct TerminalSessionHostView: NSViewRepresentable {
    let controller: any TerminalSessionControlling

    func makeNSView(context: Context) -> TerminalSessionHostingView {
        let hostingView = TerminalSessionHostingView()
        hostingView.setHostedView(controller.view)
        return hostingView
    }

    func updateNSView(_ nsView: TerminalSessionHostingView, context: Context) {
        nsView.setHostedView(controller.view)
        controller.reapplyTheme()
    }

    static func dismantleNSView(_ nsView: TerminalSessionHostingView, coordinator: ()) {
        nsView.clearHostedView()
    }
}

final class TerminalSessionHostingView: NSView {
    private weak var hostedView: NSView?
    private var hostedConstraints: [NSLayoutConstraint] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    func setHostedView(_ view: NSView) {
        guard hostedView !== view else {
            return
        }

        clearHostedView()

        if view.superview !== self {
            view.removeFromSuperview()
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        hostedView = view
        hostedConstraints = [
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ]
        NSLayoutConstraint.activate(hostedConstraints)
    }

    func clearHostedView() {
        NSLayoutConstraint.deactivate(hostedConstraints)
        hostedConstraints = []
        hostedView?.removeFromSuperview()
        hostedView = nil
    }
}
