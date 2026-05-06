import AppKit

@MainActor
final class AppKitTranscriptScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        // The autocomplete popup can visually overlap the transcript even
        // though it is owned by the composer surface. Ask the surface to consume
        // those wheel events before the transcript scroll view moves.
        if let chatSurfaceAncestor,
           chatSurfaceAncestor.consumeScrollWheelEventIfInsideComposerAutocomplete(event) == nil {
            return
        }
        super.scrollWheel(with: event)
    }

    private var chatSurfaceAncestor: AppKitChatSurfaceView? {
        var view = superview
        while let current = view {
            if let surface = current as? AppKitChatSurfaceView {
                return surface
            }
            view = current.superview
        }
        return nil
    }
}
