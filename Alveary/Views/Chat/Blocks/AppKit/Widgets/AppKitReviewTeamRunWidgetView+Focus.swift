import AppKit

/// Both the card and its nested vote disclosures rebuild controls. Preserve focus at each
/// boundary, including the outer boundary where a detached finding no longer has a window.
@MainActor
enum AppKitReviewTeamFocus {
    static func capture(in view: NSView) -> NSUserInterfaceItemIdentifier? {
        guard let responder = view.window?.firstResponder as? NSView, responder.isDescendant(of: view) else { return nil }
        return responder.identifier
    }

    static func restore(_ identifier: NSUserInterfaceItemIdentifier?, in view: NSView) {
        guard let identifier, let window = view.window, let control = descendant(identifier, in: view) else { return }
        window.makeFirstResponder(control)
    }

    private static func descendant(_ identifier: NSUserInterfaceItemIdentifier, in view: NSView) -> NSView? {
        if view.identifier == identifier { return view }
        for child in view.subviews {
            if let result = descendant(identifier, in: child) { return result }
        }
        return nil
    }
}
