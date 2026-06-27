@preconcurrency import AppKit

/// AppKit image view that draws an `NSImage` aspect-filled into its bounds.
///
/// The view is intentionally non-interactive so container preview controls can
/// own hit testing, accessibility, cursor rects, and remove-button overlays.
final class AppKitAspectFillImageView: NSView {
    var image: NSImage? {
        didSet {
            needsDisplay = true
        }
    }

    var cornerRadius: CGFloat = 0 {
        didSet {
            layer?.cornerRadius = cornerRadius
        }
    }

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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image,
              let imageFrame = aspectFillImageFrame else {
            return
        }
        image.draw(
            in: imageFrame,
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    /// Returns the image drawing rect that aspect-fills the current bounds.
    func aspectFillImageFrame(in bounds: NSRect) -> NSRect? {
        guard let image,
              image.size.width > 0,
              image.size.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            return nil
        }
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let drawSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return NSRect(
            x: bounds.midX - (drawSize.width / 2),
            y: bounds.midY - (drawSize.height / 2),
            width: drawSize.width,
            height: drawSize.height
        )
    }

    var aspectFillImageFrame: NSRect? {
        aspectFillImageFrame(in: bounds)
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = cornerRadius
    }
}

#if DEBUG
extension AppKitAspectFillImageView {
    var aspectFillImageFrameForTesting: CGRect? {
        aspectFillImageFrame
    }
}
#endif
