@preconcurrency import AppKit

@MainActor
final class AppKitComposerOverlayInfoButton: AppKitHoverInfoButton {}

#if DEBUG
extension AppKitComposerOverlayInfoButton {
    func preferredPopoverEdgeForTesting(contentSize: NSSize, visibleFrame: NSRect) -> NSRectEdge {
        preferredTooltipEdgeForTesting(contentSize: contentSize, visibleFrame: visibleFrame)
    }
}
#endif
