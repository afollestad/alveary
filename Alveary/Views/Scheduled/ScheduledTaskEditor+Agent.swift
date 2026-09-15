import SwiftUI

/// Groups the whole agent configuration; "Harness" names only its runtime choice.
struct ScheduledTaskEditorAgentSection: View {
    let viewModel: ScheduledTasksViewModel
    @Binding var draft: ScheduledTaskEditorDraft

    var body: some View {
        SettingsFormSection("Agent") {
            SettingsFormRow {
                SettingsResponsiveControlRow("Harness", horizontalControlSizing: .selectedContent) {
                    ScheduledTaskMenuPicker(
                        accessibilityLabel: "Harness",
                        selection: $draft.harnessID,
                        options: viewModel.harnessIDs(including: draft.harnessID).map {
                            .init(value: $0, label: viewModel.harnessDisplayName(for: $0))
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
                            for: draft.harnessID,
                            including: draft.modelSelection
                        ).map { .init(value: $0.value, label: $0.label) }
                    )
                }
            }

            let effortOptions = viewModel.effortOptions(
                for: draft.harnessID,
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
                            for: draft.harnessID,
                            including: draft.permissionMode
                        ).map { .init(value: $0.value, label: $0.label) }
                    )
                }
            }
        }
    }
}
