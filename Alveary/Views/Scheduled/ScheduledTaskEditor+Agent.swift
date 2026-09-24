import SwiftUI

/// Groups the whole agent configuration; the Agent row picks harness, model, and effort as one selection.
struct ScheduledTaskEditorAgentSection: View {
    let viewModel: ScheduledTasksViewModel
    @Binding var draft: ScheduledTaskEditorDraft

    var body: some View {
        SettingsFormSection("Agent") {
            SettingsFormRow {
                SettingsResponsiveControlRow("Agent", horizontalControlSizing: .selectedContent) {
                    SettingsAgentSelector(
                        accessibilityLabel: "Agent",
                        presentation: viewModel.agentPresentation(for: draft),
                        apply: { viewModel.applyAgent($0, to: &draft) }
                    )
                }
            }

            let effortOptions = viewModel.effortOptions(
                for: draft.harnessID,
                modelSelection: draft.modelSelection,
                draft: draft
            )
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
