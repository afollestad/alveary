import AppKit

enum AppPopupSurfaceStyle {
    static let backgroundAlpha: CGFloat = 0.98

    static let backgroundNSColor = NSColor(name: nil) { appearance in
        backgroundColor(for: appearance)
    }

    static func backgroundColor(for appearance: NSAppearance) -> NSColor {
        NSColor.windowBackgroundColor
            .resolved(for: appearance)
            .withAlphaComponent(backgroundAlpha)
    }

    @MainActor
    static func backgroundColor(in view: NSView) -> NSColor {
        backgroundColor(for: view.appKitRenderingAppearance)
    }
}

@MainActor
class AppKitComposerPopoverSurfaceView: NSView {
    override var isFlipped: Bool { true }
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
