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
    private var scrollObserver: (any NSObjectProtocol)?

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

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        // Released on the way out, not in `deinit`, which cannot touch main-actor state — and a
        // closing window does not always run `viewDidMoveToWindow` for its views again.
        guard newWindow == nil, let scrollObserver else {
            return
        }
        NotificationCenter.default.removeObserver(scrollObserver)
        self.scrollObserver = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeEnclosingScroll()
        // Rows are recycled into and out of the transcript under a stationary pointer, so the
        // hover state a reused view arrives with may already be wrong.
        refreshHoverFromPointerLocation()
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

    /// Scrolling moves the content under the pointer without moving the pointer, and AppKit
    /// delivers no `mouseExited` for that — the row the cursor started over keeps its highlight
    /// while the cursor is now over a different one. Re-deriving hover from the pointer's actual
    /// location on every scroll frame is what unsticks it.
    private func observeEnclosingScroll() {
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
            self.scrollObserver = nil
        }
        guard let clipView = enclosingScrollView?.contentView else {
            return
        }
        clipView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshHoverFromPointerLocation()
            }
        }
    }

    private func refreshHoverFromPointerLocation() {
        guard isInteractive, let window, window.isKeyWindow else {
            setHovered(false)
            return
        }
        let pointer = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        // The pointer can sit inside this view's bounds while the view is scrolled out of the
        // clip view, so the visible rect has to agree before the row claims the highlight.
        setHovered(bounds.contains(pointer) && visibleRect.contains(pointer))
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
