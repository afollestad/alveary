import SwiftUI

enum ScheduledTaskEditorSurface {
    case pane
    case modal
}

struct ScheduledTaskEditorContent: View {
    let viewModel: ScheduledTasksViewModel
    @Binding var draft: ScheduledTaskEditorDraft
    let title: String
    let subtitle: String?
    let submitTitle: String
    let errorMessage: String?
    let isSubmitting: Bool
    let surface: ScheduledTaskEditorSurface
    let onDismissError: () -> Void
    let onSubmit: () -> Void
    let onClose: () -> Void

    @FocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            if surface == .modal {
                Divider()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let errorMessage {
                        InlineBanner(
                            message: errorMessage,
                            severity: .error,
                            autoDismissAfter: nil,
                            onDismiss: onDismissError
                        )
                    }

                    ScheduledTaskEditorDetailsSection(
                        draft: $draft,
                        isTitleFocused: $isTitleFocused
                    )
                    ScheduledTaskEditorRecurrenceSection(draft: $draft)
                    ScheduledTaskEditorAgentSection(viewModel: viewModel, draft: $draft)
                    ScheduledTaskEditorWorkspaceSection(
                        projects: viewModel.projects,
                        draft: $draft
                    )
                }
                .padding(surface == .pane ? ContextualPaneLayout.horizontalInset : 24)
            }

            if surface == .modal {
                Divider()
            }

            footer
        }
        .onAppear {
            isTitleFocused = true
        }
        .onChange(of: draft.providerID) { _, _ in
            viewModel.normalizeProviderDependentFields(&draft)
        }
        .onChange(of: draft.modelSelection) { _, _ in
            viewModel.normalizeProviderDependentFields(&draft)
        }
        .onChange(of: viewModel.isLoadingProviders) { wasLoading, isLoading in
            guard surface == .modal, wasLoading, !isLoading else { return }
            viewModel.normalizeProviderDependentFields(&draft)
        }
        .onExitCommand(perform: onClose)
    }

    @ViewBuilder
    private var header: some View {
        switch surface {
        case .pane:
            ContextualPaneHeader(
                title,
                closeAccessibilityLabel: "Close scheduled task editor",
                onClose: onClose
            )
        case .modal:
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
                ModalCloseButton("Close scheduled task editor", action: onClose)
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch surface {
        case .pane:
            ContextualPaneFooter(
                note: { dueTimeNote },
                leadingAction: {
                    Button("Cancel", action: onClose)
                        .secondaryActionButtonStyle(expandsHorizontally: true)
                },
                trailingAction: { submitButton }
            )
        case .modal:
            HStack(spacing: 12) {
                dueTimeNote
                Spacer()
                Button("Cancel", action: onClose)
                    .secondaryActionButtonStyle()
                submitButton
            }
            .padding(20)
        }
    }

    private var dueTimeNote: some View {
        Text("Alveary must be open and your Mac awake when a task is due.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var submitButton: some View {
        Button(submitTitle, action: onSubmit)
            .primaryActionButtonStyle(expandsHorizontally: surface == .pane)
            .disabled(isSubmitting)
    }
}

struct ScheduledTaskEditorPane: View {
    let viewModel: ScheduledTasksViewModel
    let target: ScheduledTaskPaneTarget
    let onDismiss: () -> Void

    private var draft: Binding<ScheduledTaskEditorDraft> {
        Binding(
            get: { viewModel.paneSessions[target]?.draft ?? viewModel.makeNewDraft() },
            set: { viewModel.updateActiveDraft($0) }
        )
    }

    var body: some View {
        if let session = viewModel.paneSessions[target] {
            ScheduledTaskEditorContent(
                viewModel: viewModel,
                draft: draft,
                title: session.draft.isEditing ? "Edit Scheduled Task" : "New Scheduled Task",
                subtitle: nil,
                submitTitle: session.draft.isEditing ? "Save changes" : "Create task",
                errorMessage: session.errorMessage,
                isSubmitting: session.isSubmitting,
                surface: .pane,
                onDismissError: viewModel.clearEditorError,
                onSubmit: viewModel.submitActivePane,
                onClose: onDismiss
            )
        }
    }
}

// Retained as a lightweight modal host for focused editor snapshots. Production
// proposal review uses the same `ScheduledTaskEditorContent` with proposal-local state.
struct ScheduledTaskEditorSheet: View {
    let viewModel: ScheduledTasksViewModel
    let onClose: () -> Void
    @State private var draft: ScheduledTaskEditorDraft

    init(
        viewModel: ScheduledTasksViewModel,
        initialDraft: ScheduledTaskEditorDraft,
        onClose: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onClose = onClose
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        ScheduledTaskEditorContent(
            viewModel: viewModel,
            draft: $draft,
            title: draft.isEditing ? "Edit Scheduled Task" : "New Scheduled Task",
            subtitle: nil,
            submitTitle: draft.isEditing ? "Save changes" : "Create task",
            errorMessage: nil,
            isSubmitting: false,
            surface: .modal,
            onDismissError: {},
            onSubmit: {},
            onClose: onClose
        )
        .frame(minWidth: 640, idealWidth: 700, minHeight: 620, idealHeight: 760)
    }
}

private struct ScheduledTaskEditorDetailsSection: View {
    @Binding var draft: ScheduledTaskEditorDraft
    @FocusState.Binding var isTitleFocused: Bool

    var body: some View {
        SettingsFormSection("Task") {
            SettingsFormRow {
                SettingsResponsiveControlRow("Title") {
                    TextField("Daily project summary", text: $draft.title)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Scheduled task title")
                        .focused($isTitleFocused)
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
