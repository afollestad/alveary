import SwiftUI

struct ScheduledTaskEditorAgentSection: View {
    let viewModel: ScheduledTasksViewModel
    @Binding var draft: ScheduledTaskEditorDraft

    var body: some View {
        SettingsFormSection("Agent") {
            SettingsFormRow {
                SettingsResponsiveControlRow("Provider", horizontalControlSizing: .selectedContent) {
                    ScheduledTaskMenuPicker(
                        accessibilityLabel: "Provider",
                        selection: $draft.providerID,
                        options: viewModel.providerIDs(including: draft.providerID).map {
                            .init(value: $0, label: viewModel.providerDisplayName(for: $0))
                        }
                    )
                }
            }

            SettingsFormRow {
                SettingsResponsiveControlRow("Model", horizontalControlSizing: .selectedContent) {
                    ScheduledTaskMenuPicker(
                        accessibilityLabel: "Model",
                        selection: $draft.modelSelection,
                        options: viewModel.modelPickerOptions(
                            for: draft.providerID,
                            including: draft.modelSelection
                        ).map { .init(value: $0.value, label: $0.label) }
                    )
                }
            }

            let effortOptions = viewModel.effortOptions(
                for: draft.providerID,
                modelSelection: draft.modelSelection
            )
            if !effortOptions.isEmpty {
                SettingsFormRow {
                    SettingsResponsiveControlRow("Effort", horizontalControlSizing: .selectedContent) {
                        ScheduledTaskMenuPicker(
                            accessibilityLabel: "Effort",
                            selection: $draft.effort,
                            options: effortOptions.map { .init(value: $0.value, label: $0.label) }
                        )
                    }
                }
            }

            SettingsFormRow(showsDivider: false) {
                SettingsResponsiveControlRow("Permissions", horizontalControlSizing: .selectedContent) {
                    ScheduledTaskMenuPicker(
                        accessibilityLabel: "Permissions",
                        selection: $draft.permissionMode,
                        options: viewModel.permissionModeOptions(
                            for: draft.providerID,
                            including: draft.permissionMode
                        ).map { .init(value: $0.value, label: $0.label) }
                    )
                }
            }
        }
    }
}
