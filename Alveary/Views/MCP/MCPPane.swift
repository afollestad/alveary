import SwiftUI

/// What the right-pane lane mounts for an `.mcp` destination: the server form for the
/// user's own servers, the read-only tool list for a built-in group. Mirrors `SkillsPane`.
///
/// Compares equal across the lane's own render passes for the reason `MCPServerPane`
/// gives; each mounted pane keeps its own `==` beneath this one.
struct MCPPane: View, Equatable {
    let viewModel: MCPViewModel
    let target: MCPPaneTarget
    let onDismiss: () -> Void

    /// `onDismiss` is excluded: `ResizableRightPane` keys the pane by presentation
    /// identity, so a fresh closure meaning something different arrives only with a
    /// new `.id` — which tears this view down instead of comparing it.
    nonisolated static func == (lhs: MCPPane, rhs: MCPPane) -> Bool {
        lhs.viewModel === rhs.viewModel && lhs.target == rhs.target
    }

    var body: some View {
        switch target {
        case .addCustom, .addRecommended, .edit:
            MCPServerPane(viewModel: viewModel, target: target, onDismiss: onDismiss)
                .equatable()
        case .builtInToolGroup(let groupID):
            if let group = viewModel.builtInToolGroup(id: groupID) {
                BuiltInMCPToolGroupPane(group: group, onDismiss: onDismiss)
                    .equatable()
            }
        }
    }
}
