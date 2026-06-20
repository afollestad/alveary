@preconcurrency import AppKit
import SwiftUI

struct AppHoverTooltipAnchor: View {
    let text: String?

    var body: some View {
        AppHoverTooltipAnchorRepresentable(text: text)
    }
}

private struct AppHoverTooltipAnchorRepresentable: NSViewRepresentable {
    let text: String?

    func makeNSView(context: Context) -> AppKitHoverTooltipAnchorView {
        AppKitHoverTooltipAnchorView()
    }

    func updateNSView(_ nsView: AppKitHoverTooltipAnchorView, context: Context) {
        nsView.configure(helpText: text)
    }

    static func dismantleNSView(_ nsView: AppKitHoverTooltipAnchorView, coordinator: ()) {
        nsView.closeHoverTooltip()
    }
}

@MainActor
final class AppKitHoverTooltipAnchorView: NSView {
    private var trackingArea: NSTrackingArea?
    private var hoverTooltip = AppKitHoverTooltipController()
    private var helpText: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func configure(helpText: String?) {
        self.helpText = helpText
        if helpText?.isEmpty != false {
            closeHoverTooltip()
        } else if hoverTooltip.isShown {
            updateHoverTooltip()
        }
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

    override func mouseEntered(with event: NSEvent) {
        showHoverTooltip()
    }

    override func mouseExited(with event: NSEvent) {
        closeHoverTooltip()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            closeHoverTooltip()
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil {
            closeHoverTooltip()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateHoverTooltip()
    }

    func closeHoverTooltip() {
        hoverTooltip.close()
    }

    private func showHoverTooltip() {
        guard let helpText,
              !helpText.isEmpty,
              window != nil else {
            return
        }
        hoverTooltip.show(text: helpText, relativeTo: self)
    }

    private func updateHoverTooltip() {
        guard hoverTooltip.isShown,
              let helpText,
              !helpText.isEmpty,
              window != nil else {
            return
        }
        hoverTooltip.show(text: helpText, relativeTo: self)
    }
}

#if DEBUG
extension AppKitHoverTooltipAnchorView {
    func showTooltipForTesting() {
        showHoverTooltip()
    }

    var tooltipIgnoresMouseForTesting: Bool? {
        hoverTooltip.tooltipIgnoresMouse
    }

    var tooltipIsShownForTesting: Bool {
        hoverTooltip.isShown
    }
}
#endif
