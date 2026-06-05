@preconcurrency import AppKit

@MainActor
final class AppKitComposerOverlaySelectedChipView: NSView {
    private let title = "Selected"
    private let font = NSFont.systemFont(ofSize: 11, weight: .semibold)

    var measuredWidth: CGFloat {
        let width = (title as NSString).size(withAttributes: [.font: font]).width
        return ceil(width + 14)
    }

    override var isFlipped: Bool {
        true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: bounds,
            xRadius: 5,
            yRadius: 5
        )
        NSColor.secondaryLabelColor.appKitResolvedColor(in: self, alpha: 0.14).setFill()
        path.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor.appKitResolvedColor(in: self)
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        let rect = NSRect(
            x: floor((bounds.width - size.width) / 2),
            y: floor((bounds.height - size.height) / 2),
            width: size.width,
            height: size.height
        )
        (title as NSString).draw(in: rect, withAttributes: attributes)
    }
}
