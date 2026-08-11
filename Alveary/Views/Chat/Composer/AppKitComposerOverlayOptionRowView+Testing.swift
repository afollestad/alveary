#if DEBUG
@preconcurrency import AppKit

extension AppKitComposerOverlayOptionRowView {
    var isHoveringForTesting: Bool {
        isHovering
    }

    func performMouseActivationForTesting() {
        performMouseActivation()
    }
}
#endif
