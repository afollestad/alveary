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
    static let contentInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

    private weak var hostedView: NSView?
    private var hostedConstraints: [NSLayoutConstraint] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        applyPaletteBackground()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        applyPaletteBackground()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyPaletteBackground()
    }

    func setHostedView(_ view: NSView) {
        guard hostedView !== view else {
            return
        }

        clearHostedView()

        if let previousSuperview = view.superview,
           previousSuperview !== self {
            if let previousHost = previousSuperview as? TerminalSessionHostingView {
                previousHost.clearHostedView()
            } else {
                view.removeFromSuperview()
            }
        }

        if view.superview !== self {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        hostedView = view
        let insets = Self.contentInsets
        hostedConstraints = [
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            view.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom)
        ]
        NSLayoutConstraint.activate(hostedConstraints)
    }

    func clearHostedView() {
        NSLayoutConstraint.deactivate(hostedConstraints)
        hostedConstraints = []
        if hostedView?.superview === self {
            hostedView?.removeFromSuperview()
        }
        hostedView = nil
    }

    private func applyPaletteBackground() {
        wantsLayer = true
        layer?.backgroundColor = TerminalThemePalette
            .resolved(for: effectiveAppearance)
            .background
            .cgColor
    }
}
