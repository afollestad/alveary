import AppKit
import QuartzCore

@MainActor
extension AppKitTranscriptDocumentLayoutView {
    func removeObsoleteView(_ view: NSView) {
        guard canAnimateRemovedThoughtView(view) else {
            view.removeFromSuperview()
            return
        }

        // Exiting thought rows are no longer part of layout. Keep only their old
        // view around long enough to fade out while live rows reflow underneath.
        let viewID = ObjectIdentifier(view)
        guard !exitingThoughtViewIDs.contains(viewID) else {
            return
        }
        exitingThoughtViewIDs.insert(viewID)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = appExpansionAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            view.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                view.removeFromSuperview()
                self.exitingThoughtViewIDs.remove(viewID)
            }
        }
    }

    func canAnimateRemovedThoughtView(_ view: NSView) -> Bool {
        guard window != nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let rowID = view.identifier?.rawValue
        else {
            return false
        }
        return AppKitTranscriptTransientRows.isThoughtRowID(rowID)
    }
}
