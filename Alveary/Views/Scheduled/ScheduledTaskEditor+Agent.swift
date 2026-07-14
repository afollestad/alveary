import SwiftUI

struct ScheduledTaskEditorAgentSection: View {
    let viewModel: ScheduledTasksViewModel
    @Binding var draft: ScheduledTaskEditorDraft

    var body: some View {
        SettingsFormSection("Agent") {
            SettingsFormRow {
                SettingsResponsiveControlRow("Provider", horizontalControlSizing: .intrinsic) {
                    Picker("Provider", selection: $draft.providerID) {
                        ForEach(viewModel.providerIDs(including: draft.providerID), id: \.self) { providerID in
                            Text(viewModel.providerDisplayName(for: providerID)).tag(providerID)
                        }
                    }
                    .labelsHidden()
                }
            }

            SettingsFormRow {
                SettingsResponsiveControlRow("Model", horizontalControlSizing: .intrinsic) {
                    Picker("Model", selection: $draft.modelSelection) {
                        ForEach(
                            viewModel.modelPickerOptions(for: draft.providerID, including: draft.modelSelection)
                        ) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .labelsHidden()
                }
            }

            let effortOptions = viewModel.effortOptions(
                for: draft.providerID,
                modelSelection: draft.modelSelection
            )
            if !effortOptions.isEmpty {
                SettingsFormRow {
                    SettingsResponsiveControlRow("Effort", horizontalControlSizing: .intrinsic) {
                        Picker("Effort", selection: $draft.effort) {
                            ForEach(effortOptions) { option in
                                Text(option.label).tag(option.value)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }

            SettingsFormRow(showsDivider: false) {
                SettingsResponsiveControlRow("Permissions", horizontalControlSizing: .intrinsic) {
                    Picker("Permissions", selection: $draft.permissionMode) {
                        ForEach(
                            viewModel.permissionModeOptions(
                                for: draft.providerID,
                                including: draft.permissionMode
                            )
                        ) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .labelsHidden()
                }
            }
        }
    }
}
