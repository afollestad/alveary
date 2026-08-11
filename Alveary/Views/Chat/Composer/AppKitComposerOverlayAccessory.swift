@preconcurrency import AppKit

/// An optional settings control an overlay can host in its footer, left of Dismiss/Submit.
///
/// Only `ExitPlanMode` uses it today: approving a plan is the point where the user may want to
/// implement on a different model than they planned on. `AskUserQuestion` overlays leave this `nil`
/// so their geometry is unchanged — answer controls there are the option rows only.
struct AppKitComposerOverlayAccessory {
    let selection: ChatComposerActionRowView.ReasoningSelection
    let reasoning: ChatComposerActionRowView.ReasoningConfiguration
    let isEnabled: Bool
}
