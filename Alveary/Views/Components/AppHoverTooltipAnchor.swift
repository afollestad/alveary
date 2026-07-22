@preconcurrency import AppKit
import SwiftUI

struct AppHoverTooltipAnchor: View {
    let text: String?
    let onHover: ((Bool) -> Void)?

    init(text: String?, onHover: ((Bool) -> Void)? = nil) {
        self.text = text
        self.onHover = onHover
    }

    var body: some View {
        AppHoverTooltipAnchorRepresentable(text: text, onHover: onHover)
    }
}

private struct AppHoverTooltipAnchorRepresentable: NSViewRepresentable {
    let text: String?
    let onHover: ((Bool) -> Void)?

    func makeNSView(context: Context) -> AppKitHoverTooltipAnchorView {
        AppKitHoverTooltipAnchorView()
    }

    func updateNSView(_ nsView: AppKitHoverTooltipAnchorView, context: Context) {
        nsView.configure(helpText: text, onHover: onHover)
    }

    static func dismantleNSView(_ nsView: AppKitHoverTooltipAnchorView, coordinator: ()) {
        nsView.endHoverTracking()
    }
}

@MainActor
final class AppKitHoverTooltipAnchorView: NSView {
    private var trackingArea: NSTrackingArea?
    private var hoverTooltip = AppKitHoverTooltipController()
    private var helpText: String?
    private var onHover: ((Bool) -> Void)?
    private var isHovering = false

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

    func configure(helpText: String?, onHover: ((Bool) -> Void)? = nil) {
        // Hover-driven SwiftUI state can refresh this representable while its popover is open.
        // Rebuilding unchanged content during that refresh can collapse the measured wrapped height.
        let helpTextChanged = self.helpText != helpText
        self.helpText = helpText
        self.onHover = onHover
        if helpText?.isEmpty != false {
            closeHoverTooltip()
        } else if helpTextChanged, hoverTooltip.isShown {
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
        setHovering(true)
        showHoverTooltip()
    }

    override func mouseExited(with event: NSEvent) {
        setHovering(false)
        closeHoverTooltip()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            endHoverTracking()
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil {
            endHoverTracking()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateHoverTooltip()
    }

    func closeHoverTooltip() {
        hoverTooltip.close()
    }

    func endHoverTracking() {
        setHovering(false)
        closeHoverTooltip()
    }

    private func setHovering(_ isHovering: Bool) {
        guard self.isHovering != isHovering else {
            return
        }
        self.isHovering = isHovering
        onHover?(isHovering)
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
    func setHoveringForTesting(_ isHovering: Bool) {
        setHovering(isHovering)
    }

    func showTooltipForTesting() {
        guard let helpText,
              !helpText.isEmpty,
              window != nil else {
            return
        }
        hoverTooltip.showForTesting(text: helpText)
    }

    var tooltipIgnoresMouseForTesting: Bool? {
        hoverTooltip.tooltipIgnoresMouse
    }

    var tooltipIsShownForTesting: Bool {
        hoverTooltip.isShown
    }

    var tooltipContentBuildCountForTesting: Int {
        hoverTooltip.contentBuildCountForTesting
    }
}
#endif
