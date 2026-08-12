import SwiftUI

/// The width the right-pane lane's main-content slot will have once the lane's current
/// presentation animation settles: the full slot while the lane is hidden or dismissing,
/// the slot minus pane and handle while a pane is presented or presenting. `nil` outside
/// the lane (snapshots, previews).
///
/// Published so width-reactive layouts can react to a presentation the moment it starts
/// and ride the slide's own curve. Reacting to live geometry instead waits for the width
/// to cross the layout's threshold, which can sit anywhere in the slide — near the end,
/// the layout change trails the slide as a distinct second beat.
///
/// `ResizableRightPane` can publish this because its `presentationProgress` state is only
/// ever written 0 or 1 — the in-flight interpolation lives in
/// `RightPanePresentationLayout.animatableData` — so the lane's body always reads the
/// slide's target, never a mid-flight fraction.
struct RightPaneSettledMainWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var rightPaneSettledMainWidth: CGFloat? {
        get { self[RightPaneSettledMainWidthKey.self] }
        set { self[RightPaneSettledMainWidthKey.self] = newValue }
    }

    var rightPaneHasSettled: Bool {
        get { self[RightPaneHasSettledKey.self] }
        set { self[RightPaneHasSettledKey.self] = newValue }
    }
}

/// Whether the lane's entrance slide has finished for the pane content reading this.
///
/// Published into `paneContent` so a pane can defer its *heavy first layout* — a full
/// markdown document, say — until the slide has settled. Laying such content out on the
/// pane's first frames stalls the main thread mid-animation, which freezes the slide for
/// the document's whole layout cost and reads as a dead beat after the click.
///
/// Defaults to `true` so snapshots and previews, which host panes without the lane,
/// render the full content immediately. A pane that adopts this must latch the first
/// `true` it observes: the lane deactivates its resize handle (the signal's source) when
/// a dismissal begins, and un-latching mid-retract would swap live content back to its
/// placeholder while sliding out.
struct RightPaneHasSettledKey: EnvironmentKey {
    static let defaultValue = true
}
