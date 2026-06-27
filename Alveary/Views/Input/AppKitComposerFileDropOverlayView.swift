@preconcurrency import AppKit

/// Visual drag-and-drop affordance drawn over the composer editor and attachment strip.
///
/// `AppKitChatComposerPanelView` owns the drag destination events; this view is
/// intentionally display-only so ordinary mouse and keyboard interaction keeps
/// flowing to the attachment strip and BlockInputKit editor underneath.
@MainActor
final class AppKitComposerFileDropOverlayView: NSView {
    private static let borderWidth: CGFloat = 1.5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        let rect = bounds.insetBy(dx: Self.borderWidth / 2, dy: Self.borderWidth / 2)
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: AppKitChatComposerEditorController.editorCornerRadius,
            yRadius: AppKitChatComposerEditorController.editorCornerRadius
        )
        let accentColor = NSColor.controlAccentColor.resolved(for: appKitRenderingAppearance)
        accentColor.withAlphaComponent(0.16).setFill()
        path.fill()
        accentColor.withAlphaComponent(0.55).setStroke()
        path.lineWidth = Self.borderWidth
        path.stroke()
    }

    private func setup() {
        isHidden = true
        alphaValue = 0
        wantsLayer = true
        layer?.masksToBounds = false
        setAccessibilityElement(false)
    }
}
