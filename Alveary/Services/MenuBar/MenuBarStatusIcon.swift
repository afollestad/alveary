import AppKit

/// The status item's two images: the bee alone, and the bee with a dot cut into its top-right
/// corner while pull requests wait on the viewer's review.
///
/// Both stay `isTemplate`, so macOS keeps tinting them for light, dark, and highlighted menu
/// bars — a coloured badge would have to give that up. In a one-colour image the dot is only
/// legible with a gap around it, so the bee is drawn clipped away from a ring there.
@MainActor
enum MenuBarStatusIcon {
    /// Sized against the 18pt bee: the ring clears the right antenna's tip but stays off the
    /// head, so the badge reads as added rather than as a bite out of the icon.
    private static let dotRadius: CGFloat = 2.5
    private static let cutoutRadius: CGFloat = 3.75
    /// The dot's centre, inset from the image's top and right edges.
    private static let dotInset: CGFloat = 2.75

    private static let plainImage: NSImage? = {
        let image = NSImage(named: MenuBarController.templateImageName)
        image?.isTemplate = true
        return image
    }()

    /// A drawing-handler image re-renders per backing store, so it stays crisp on any display
    /// scale; `lockFocus` would bake in whichever scale happened to be current.
    ///
    /// The gap is an even-odd clip rather than a `.clear` fill: the handler can draw straight into
    /// its destination, where clearing would erase whatever lies beneath the icon too.
    private static let badgedImage: NSImage? = {
        guard let plainImage else {
            return nil
        }
        let image = NSImage(size: plainImage.size, flipped: false) { rect in
            let center = NSPoint(x: rect.maxX - dotInset, y: rect.maxY - dotInset)
            NSGraphicsContext.saveGraphicsState()
            let clip = NSBezierPath(rect: rect)
            clip.appendOval(in: circleRect(center: center, radius: cutoutRadius))
            clip.windingRule = .evenOdd
            clip.addClip()
            plainImage.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: circleRect(center: center, radius: dotRadius)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    static func image(badged: Bool) -> NSImage? {
        badged ? badgedImage : plainImage
    }

    private static func circleRect(center: NSPoint, radius: CGFloat) -> NSRect {
        NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
