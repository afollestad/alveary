import AppKit

/// The card's own surface.
///
/// A pull-request link card is clicked as a whole, so hover, cursor, and the press belong to
/// the bubble rather than the row view, which spans the transcript's full width and would
/// otherwise light up far outside the card.
///
/// Open to subclassing so a leaf control inside a card — the review proposal's per-comment Remove —
/// gets the same press, cursor, role, and scroll-aware hover instead of re-deriving them.
class AppKitHostToolWidgetBubbleView: AppKitDynamicColorView {
    var onActivate: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private(set) var isHovered = false
    private var trackingArea: NSTrackingArea?
    private var geometryObservers: [any NSObjectProtocol] = []

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
        guard newWindow == nil else {
            return
        }
        releaseGeometryObservers()
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
    ///
    /// A *resize* does the same thing and posts no bounds change: `boundsDidChangeNotification`
    /// fires only when the bounds move independently of the frame. Opening the right pane narrows
    /// the transcript and reflows it under a stationary pointer, so the frame notification is
    /// needed too — without it a card clicked to open a pane keeps its highlight afterwards.
    private func observeEnclosingScroll() {
        releaseGeometryObservers()
        guard let clipView = enclosingScrollView?.contentView else {
            return
        }
        clipView.postsBoundsChangedNotifications = true
        clipView.postsFrameChangedNotifications = true
        geometryObservers = [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification]
            .map { name in
                NotificationCenter.default.addObserver(forName: name, object: clipView, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.refreshHoverFromPointerLocation()
                    }
                }
            }
    }

    private func releaseGeometryObservers() {
        for observer in geometryObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        geometryObservers = []
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
