import AppKit

/// The card's own surface.
///
/// A pull-request link card is clicked as a whole, so hover, cursor, and the press belong to
/// the bubble rather than the row view, which spans the transcript's full width and would
/// otherwise light up far outside the card.
final class AppKitHostToolWidgetBubbleView: AppKitDynamicColorView {
    var onActivate: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private(set) var isHovered = false
    private var trackingArea: NSTrackingArea?

    var isInteractive = false {
        didSet {
            guard isInteractive != oldValue else {
                return
            }
            // A card that stops being a button must not keep a hover highlight it can no
            // longer clear, since its tracking area goes with it.
            setHovered(false)
            setAccessibilityElement(isInteractive)
            setAccessibilityRole(isInteractive ? .button : .group)
            refreshTrackingArea()
            window?.invalidateCursorRects(for: self)
        }
    }

    override var isFlipped: Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshTrackingArea()
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
    }

    override func mouseDown(with event: NSEvent) {
        // Consumed so the matching mouse-up is delivered here instead of travelling up the
        // responder chain; the press itself resolves on mouse-up, like a button.
        guard isInteractive else {
            super.mouseDown(with: event)
            return
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isInteractive,
              bounds.contains(convert(event.locationInWindow, from: nil)) else {
            super.mouseUp(with: event)
            return
        }
        onActivate?()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isInteractive else {
            return
        }
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func accessibilityPerformPress() -> Bool {
        guard isInteractive else {
            return false
        }
        onActivate?()
        return true
    }

    private func setHovered(_ isHovered: Bool) {
        guard self.isHovered != isHovered else {
            return
        }
        self.isHovered = isHovered
        onHoverChanged?(isHovered)
    }

    private func refreshTrackingArea() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
        guard isInteractive else {
            return
        }
        let newTrackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }
}
