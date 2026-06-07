import AppKit

@MainActor
enum AppKitComposerPopoverSurface {
    static let cornerRadius: CGFloat = 12

    static func fillColor(in view: NSView) -> NSColor {
        NSColor.windowBackgroundColor.appKitResolvedColor(in: view, alpha: 0.98)
    }

    static func draw(in view: NSView, bounds: NSRect) {
        fillColor(in: view).setFill()
        NSBezierPath(
            roundedRect: bounds,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        ).fill()
    }
}

@MainActor
class AppKitComposerPopoverSurfaceView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        AppKitComposerPopoverSurface.draw(in: self, bounds: bounds)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

@MainActor
final class AppKitComposerPopoverDividerView: NSView {
    static let height: CGFloat = 1
    static let horizontalInset: CGFloat = 14
    static let alpha: CGFloat = 0.10

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateDividerColor()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateDividerColor()
    }

    private func updateDividerColor() {
        // Composer popovers share this divider so dynamic colors and line weight
        // stay consistent across the `+`, reasoning, and model menus.
        layer?.backgroundColor = NSColor.labelColor
            .appKitResolvedColor(in: self, alpha: Self.alpha)
            .cgColor
    }
}
