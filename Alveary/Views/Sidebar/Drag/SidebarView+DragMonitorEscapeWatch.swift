import AppKit

extension SidebarDragMonitorView {
    /// A drag runs inside AppKit's mouse-tracking loop, which dequeues only mouse events, so the
    /// local event monitor never sees the Escape key press. Poll the hardware key state instead,
    /// on `.common` so the timer still fires while tracking.
    func startEscapeWatch() {
        guard escapeWatchTimer == nil else {
            return
        }
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
    }

    func performEscapeWatchTick() {
        guard interactionState.activeSessionID != nil,
              CGEventSource.keyState(.combinedSessionState, key: SidebarDragKeyCode.escape) else {
            return
        }
        stopAutoscroll()
        stopEscapeWatch()
        onEscape?()
    }
}
