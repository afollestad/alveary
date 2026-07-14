import SwiftUI

struct ScheduledTaskEditorSheet: View {
    let viewModel: ScheduledTasksViewModel
    let onClose: () -> Void
    private let titleOverride: String?
    private let subtitleOverride: String?
    private let submitTitleOverride: String?
    private let errorMessageOverride: String?
    private let onDismissErrorOverride: (() -> Void)?
    private let onSubmit: (ScheduledTaskEditorDraft) -> Bool
    private let minimumWidth: CGFloat
    private let minimumHeight: CGFloat

    @State private var draft: ScheduledTaskEditorDraft

    init(
        viewModel: ScheduledTasksViewModel,
        initialDraft: ScheduledTaskEditorDraft,
        onClose: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onClose = onClose
        self.titleOverride = nil
        self.subtitleOverride = nil
        self.submitTitleOverride = nil
        self.errorMessageOverride = nil
        self.onDismissErrorOverride = nil
        self.onSubmit = { draft in viewModel.save(draft) }
        self.minimumWidth = 640
        self.minimumHeight = 620
        _draft = State(initialValue: initialDraft)
    }

    init(
        viewModel: ScheduledTasksViewModel,
        initialDraft: ScheduledTaskEditorDraft,
        title: String,
        subtitle: String,
        submitTitle: String,
        errorMessage: String?,
        onDismissError: @escaping () -> Void,
        onSubmit: @escaping (ScheduledTaskEditorDraft) -> Bool,
        onClose: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onClose = onClose
        self.titleOverride = title
        self.subtitleOverride = subtitle
        self.submitTitleOverride = submitTitle
        self.errorMessageOverride = errorMessage
        self.onDismissErrorOverride = onDismissError
        self.onSubmit = onSubmit
        self.minimumWidth = 0
        self.minimumHeight = 0
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let errorMessage = errorMessageOverride ?? viewModel.editorErrorMessage {
                        InlineBanner(
                            message: errorMessage,
                            severity: .error,
                            autoDismissAfter: nil,
                            onDismiss: dismissError
                        )
                    }

                    ScheduledTaskEditorDetailsSection(draft: $draft)
                    ScheduledTaskEditorRecurrenceSection(draft: $draft)
                    ScheduledTaskEditorAgentSection(viewModel: viewModel, draft: $draft)
                    ScheduledTaskEditorWorkspaceSection(
                        projects: viewModel.projects,
                        draft: $draft
                    )
                }
                .padding(24)
            }

            Divider()

            footer
        }
        .frame(minWidth: minimumWidth, idealWidth: 700, minHeight: minimumHeight, idealHeight: 760)
        .onChange(of: draft.providerID) { _, _ in
            viewModel.normalizeProviderDependentFields(&draft)
        }
        .onChange(of: draft.modelSelection) { _, _ in
            viewModel.normalizeProviderDependentFields(&draft)
        }
        .onChange(of: viewModel.isLoadingProviders) { wasLoading, isLoading in
            guard wasLoading, !isLoading else { return }
            viewModel.normalizeProviderDependentFields(&draft)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(titleOverride ?? (draft.isEditing ? "Edit scheduled task" : "New scheduled task"))
                    .font(.title2.weight(.semibold))
                Text(subtitleOverride ?? "Changes apply only to future runs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ModalCloseButton("Close scheduled task editor", action: onClose)
        }
        .padding(24)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("Alveary must be open and your Mac awake when a task is due.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Cancel", action: onClose)
                .secondaryActionButtonStyle()
            Button(submitTitleOverride ?? (draft.isEditing ? "Save changes" : "Create task")) {
                if onSubmit(draft) {
                    onClose()
                }
            }
            .primaryActionButtonStyle()
        }
        .padding(20)
    }

    private func dismissError() {
        if let onDismissErrorOverride {
            onDismissErrorOverride()
        } else {
            viewModel.clearEditorError()
        }
    }
}

private struct ScheduledTaskEditorDetailsSection: View {
    @Binding var draft: ScheduledTaskEditorDraft

    var body: some View {
        SettingsFormSection("Task") {
            SettingsFormRow {
                SettingsResponsiveControlRow("Title") {
                    TextField("Daily project summary", text: $draft.title)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Scheduled task title")
                }
            }

            SettingsFormRow(showsDivider: false) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Instructions")
                    TextEditor(text: $draft.prompt)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.25))
                        )
                        .accessibilityLabel("Scheduled task instructions")
                }
            }
        }
    }
}
