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
                        selection: Binding(get: { draft.harnessID }, set: {
                            draft.harnessID = $0
                            viewModel.normalizeHarnessDependentFields(&draft, explicitSelectionChange: true)
                        }),
                        options: viewModel.editorHarnessIDs(for: draft).map {
                            .init(value: $0, label: viewModel.harnessDisplayName(for: $0))
                        }
                    )
                }
            }

            SettingsFormRow {
                SettingsResponsiveControlRow("Model", horizontalControlSizing: .selectedContent) {
                    ScheduledTaskMenuPicker(
                        accessibilityLabel: "Model",
                        selection: Binding(get: { draft.modelSelection }, set: {
                            draft.modelSelection = $0
                            viewModel.normalizeHarnessDependentFields(&draft, explicitSelectionChange: true)
                        }),
                        options: viewModel.modelPickerOptions(
                            for: draft.harnessID,
                            including: draft.modelSelection,
                            draft: draft
                        ).map { .init(value: $0.value, label: $0.label) }
                    )
                }
            }

            let effortOptions = viewModel.effortOptions(
                for: draft.harnessID,
                modelSelection: draft.modelSelection,
                draft: draft
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
            if draft.harnessID == "opencode", draft.effort != AppSettings.openCodeDefaultEffort,
               !viewModel.isOpenCodeEditorCatalogPending(for: draft),
               !effortOptions.contains(where: { $0.value == draft.effort }) {
                SettingsFormRow {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("The saved reasoning variant is unavailable for this model.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Use model default") { draft.effort = AppSettings.openCodeDefaultEffort }
                            .buttonStyle(.link)
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
        .task(id: viewModel.openCodeDiscoveryDirectory(for: draft)) {
            await viewModel.refreshOpenCodeEditorCatalog(directory: viewModel.openCodeDiscoveryDirectory(for: draft))
        }
    }
}
