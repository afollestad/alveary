import AppKit

extension SidebarDragMonitorView {
    /// A drag runs inside AppKit's mouse-tracking loop, which dequeues only mouse events, so the
    /// local event monitor never sees the Escape key press. Poll the hardware key state instead,
    /// on `.common` so the timer still fires while tracking.
    ///
    /// The same tick polls the mouse button, because a tracking loop that swallows the mouse-up
    /// too leaves the sidebar in a drag no event can ever finish. `SidebarSectionHeaderRow`'s
    /// `rowToggleGesture` documents the loop that did exactly that; this is the backstop for
    /// whatever else reaches it.
    func startEscapeWatch() {
        guard escapeWatchTimer == nil else {
            return
        }
        pointerReleasedTicks = 0
        let timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performEscapeWatchTick()
            }
        }
        escapeWatchTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopEscapeWatch() {
        escapeWatchTimer?.invalidate()
        escapeWatchTimer = nil
        pointerReleasedTicks = 0
    }

    func performEscapeWatchTick() {
        guard interactionState.activeSessionID != nil else {
            pointerReleasedTicks = 0
            return
        }
        let action = sidebarDragWatchAction(
            isEscapePressed: CGEventSource.keyState(.combinedSessionState, key: SidebarDragKeyCode.escape),
            isPointerDown: CGEventSource.buttonState(.combinedSessionState, button: .left),
            pointerReleasedTicks: pointerReleasedTicks
        )
        switch action {
        case .keepWatching:
            pointerReleasedTicks = 0
        case .countPointerRelease:
            pointerReleasedTicks += 1
        case .escape:
            stopAutoscroll()
            stopEscapeWatch()
            onEscape?()
        case .abandon:
            stopAutoscroll()
            stopEscapeWatch()
            onPointerLost?()
        }
    }
}

/// What one watch tick should do about a drag the monitor may no longer be receiving events for.
///
/// The pointer-release count exists so the ordinary mouse-up wins the race: `handleSidebarMonitorMouseUp`
/// finalizes on the next runloop turn, well inside the second tick this requires before giving up.
func sidebarDragWatchAction(
    isEscapePressed: Bool,
    isPointerDown: Bool,
    pointerReleasedTicks: Int
) -> SidebarDragWatchAction {
    if isEscapePressed {
        return .escape
    }
    guard !isPointerDown else {
        return .keepWatching
    }
    return pointerReleasedTicks >= 1 ? .abandon : .countPointerRelease
}

enum SidebarDragWatchAction: Equatable {
    case keepWatching
    case countPointerRelease
    /// Escape is held: cancel the drag but leave the session waiting for the real mouse-up.
    case escape
    /// The pointer came up without the monitor ever seeing it: drop the drag outright, because
    /// nothing else will ever end it.
    case abandon
}
