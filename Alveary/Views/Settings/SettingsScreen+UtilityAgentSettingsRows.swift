import SwiftUI

/// Rows for the `utility*` settings, hosted by the Git tab's `Commit & PR generation` card beneath the prompts they run.
/// Unlike those prompts, these settings apply only when no thread conversation can write the text itself.
struct UtilityAgentSettingsRows: View {
    let viewModel: SettingsViewModel

    var body: some View {
        SettingsFormRow(showsDivider: viewModel.utilityUnavailableMessage != nil) {
            SettingsResponsiveControlRow(
                "Agent",
                helpText: "Writes commit messages and pull request descriptions outside a thread conversation, such as from a project. "
                    + "Inside one, the thread's own agent writes them.",
                horizontalControlSizing: .intrinsic
            ) {
                SettingsAgentSelector(
                    accessibilityLabel: "Commit and PR generation agent",
                    presentation: viewModel.utilityAgentPresentation,
                    apply: { viewModel.applyUtilityAgent($0) }
                )
            }
        }
        if let message = viewModel.utilityUnavailableMessage {
            SettingsFormRow(showsDivider: false) {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
