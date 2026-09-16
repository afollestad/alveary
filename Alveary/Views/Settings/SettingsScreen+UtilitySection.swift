import SwiftUI

/// Read-only project helpers share an explicit provider selection independent of interactive task defaults.
struct UtilitySettingsSection: View {
    let viewModel: SettingsViewModel

    var body: some View {
        SettingsFormSection("Utility") {
            SettingsFormRow {
                SettingsResponsiveControlRow(
                    "Harness",
                    helpText: "Used for commit messages and pull request descriptions.",
                    horizontalControlSizing: .intrinsic
                ) {
                    SettingsMenuPicker(
                        "Utility harness",
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
                            "Utility model",
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
                                "Utility effort",
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
}
