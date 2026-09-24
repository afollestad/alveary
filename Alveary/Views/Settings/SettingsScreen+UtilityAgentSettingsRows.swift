import SwiftUI

/// Rows for the `utility*` settings, hosted by the Git tab's `Commit & PR generation` card beneath the prompts they run.
/// Unlike those prompts, these settings apply only when no thread conversation can write the text itself.
struct UtilityAgentSettingsRows: View {
    let viewModel: SettingsViewModel

    var body: some View {
        SettingsFormRow {
            SettingsResponsiveControlRow(
                "Harness",
                helpText: "Writes commit messages and pull request descriptions outside a thread conversation, such as from a project. "
                    + "Inside one, the thread's own agent writes them.",
                horizontalControlSizing: .intrinsic
            ) {
                SettingsMenuPicker(
                    "Commit and PR generation harness",
                    selection: Binding(get: { viewModel.utilityHarnessSelection }, set: viewModel.setUtilityHarness),
                    options: viewModel.utilityHarnessOptions,
                    label: viewModel.utilityHarnessLabel
                )
            }
        }
        if viewModel.canConfigureUtilityModel {
            SettingsFormRow(showsDivider: !viewModel.utilityEffortOptions.isEmpty || viewModel.utilityUnavailableMessage != nil) {
                SettingsResponsiveControlRow("Model", horizontalControlSizing: .intrinsic) {
                    SettingsMenuPicker(
                        "Commit and PR generation model",
                        selection: Binding(get: { viewModel.utilityModelSelection }, set: viewModel.setUtilityModel),
                        options: viewModel.utilityModelOptions,
                        label: viewModel.utilityModelLabel
                    )
                }
            }
            if !viewModel.utilityEffortOptions.isEmpty {
                SettingsFormRow(showsDivider: viewModel.utilityUnavailableMessage != nil) {
                    SettingsResponsiveControlRow("Effort", horizontalControlSizing: .intrinsic) {
                        SettingsMenuPicker(
                            "Commit and PR generation effort",
                            selection: Binding(get: { viewModel.utilityEffortSelection }, set: viewModel.setUtilityEffort),
                            options: viewModel.utilityEffortOptions,
                            label: viewModel.utilityEffortLabel
                        )
                    }
                }
            }
        }
        if let message = viewModel.utilityUnavailableMessage {
            SettingsFormRow(showsDivider: false) {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
