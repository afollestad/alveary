@preconcurrency import AppKit
import SwiftUI

extension View {
    // Disabled SwiftUI controls do not install a blocked cursor by default on macOS.
    func blockedCursorOverlay(when isActive: Bool) -> some View {
        overlay {
            if isActive {
                GeometryReader { proxy in
                    BlockedCursorOverlay()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .allowsHitTesting(true)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

private struct BlockedCursorOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> BlockedCursorView {
        BlockedCursorView(frame: .zero)
    }

    func updateNSView(_ nsView: BlockedCursorView, context: Context) {
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

private final class BlockedCursorView: NSView {
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool {
        true
    }

    override var isOpaque: Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .operationNotAllowed)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.operationNotAllowed.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.operationNotAllowed.set()
    }
}
