import AppKit

/// Both the card and its nested vote disclosures rebuild controls. Preserve focus at each
/// boundary, including the outer boundary where a detached finding no longer has a window.
@MainActor
enum AppKitReviewTeamFocus {
    struct Snapshot {
        let identifier: NSUserInterfaceItemIdentifier
        let reviewerPresentation: AppKitReviewTeamReviewerRowView.FocusPresentation?
    }

    static func capture(in view: NSView) -> Snapshot? {
        guard let responder = view.window?.firstResponder as? NSView,
              responder.isDescendant(of: view), let identifier = responder.identifier else { return nil }
        return Snapshot(identifier: identifier, reviewerPresentation: (responder as? AppKitReviewTeamReviewerRowView)?.focusPresentation)
    }

    static func restore(_ snapshot: Snapshot?, in view: NSView) {
        guard let snapshot, let window = view.window, let control = descendant(snapshot.identifier, in: view) else { return }
        if let presentation = snapshot.reviewerPresentation, let reviewer = control as? AppKitReviewTeamReviewerRowView {
            reviewer.focusPresentation = presentation
        }
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
