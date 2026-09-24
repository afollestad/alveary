import SwiftUI

/// Route-qualified controls keep review and feedback pins independent and distinguishable to VoiceOver.
struct PullRequestAgentSettingsRows: View {
    enum Route {
        case review
        case addressFeedback

        var label: String { self == .review ? "Review" : "Address feedback" }
    }

    let viewModel: SettingsViewModel
    let route: Route
    var showsFinalDivider = false

    var body: some View {
        let editor = route == .review ? viewModel.reviewAgentEditor : viewModel.addressFeedbackAgentEditor
        SettingsFormRow {
            SettingsResponsiveControlRow("Agent", helpText: agentHelp, horizontalControlSizing: .intrinsic) {
                SettingsAgentSelector(
                    accessibilityLabel: "\(route.label) agent",
                    presentation: editor.presentation,
                    apply: { editor.apply($0) }
                )
            }
        }
        SettingsFormRow(showsDivider: showsFinalDivider) {
            SettingsResponsiveControlRow(
                "Permission mode",
                helpText: "Permissions for \(route.label.lowercased()) tasks. Review-team workers always run read-only.",
                horizontalControlSizing: .intrinsic
            ) {
                SettingsMenuPicker(
                    "\(route.label) permission mode",
                    selection: Binding(get: { editor.permissionSelection }, set: editor.setPermission),
                    options: editor.permissionOptions,
                    label: editor.label(forPermission:)
                )
            }
        }
    }
}

private extension PullRequestAgentSettingsRows {
    var agentHelp: String {
        route == .review
            ? "The agent used for single-agent reviews. In team mode, edit the lead in Manage."
            : "The agent used to address pull request feedback, independent of review settings."
    }
}
