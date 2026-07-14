import SwiftUI

struct ScheduledTasksScreen: View {
    let viewModel: ScheduledTasksViewModel

    @State private var selectedFilter = ScheduledTasksFilter.all
    @State private var deleteConfirmation: ScheduledTaskRowPresentation?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ScheduledTasksScreenHeader(
                    selectedFilter: $selectedFilter,
                    onCreate: viewModel.requestCreate
                )

                if let errorMessage = viewModel.errorMessage {
                    InlineBanner(
                        message: errorMessage,
                        severity: .error,
                        autoDismissAfter: nil,
                        onDismiss: viewModel.clearError
                    )
                }

                let visibleTasks = viewModel.tasks(for: selectedFilter)
                if visibleTasks.isEmpty {
                    ScheduledTasksEmptyState(
                        filter: selectedFilter,
                        onCreate: viewModel.requestCreate
                    )
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleTasks) { task in
                            ScheduledTaskRow(
                                task: task,
                                providerName: viewModel.providerDisplayName(for: task.providerID),
                                isRunNowPending: viewModel.pendingRunNowDefinitionIDs.contains(task.id),
                                onEdit: {
                                    viewModel.requestEdit(definitionID: task.id)
                                },
                                onPause: { viewModel.pause(task) },
                                onResume: { viewModel.resume(task) },
                                onRunNow: { viewModel.runNow(task) },
                                onDelete: { deleteConfirmation = task }
                            )
                        }
                    }
                }
            }
            .padding(28)
        }
        .task {
            await viewModel.load()
        }
        .sheet(item: editorDraftBinding) { draft in
            ScheduledTaskEditorSheet(viewModel: viewModel, initialDraft: draft) {
                viewModel.dismissEditor()
            }
        }
        .confirmationDialog(
            "Delete scheduled task?",
            isPresented: Binding(
                get: { deleteConfirmation != nil },
                set: { isPresented in
                    if !isPresented {
                        deleteConfirmation = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: deleteConfirmation
        ) { task in
            Button("Delete", role: .destructive) {
                viewModel.delete(task)
                deleteConfirmation = nil
            }
            Button("Cancel", role: .cancel) {
                deleteConfirmation = nil
            }
        } message: { _ in
            Text("Future runs will stop. Existing run history and Task threads are retained.")
        }
    }

    private var editorDraftBinding: Binding<ScheduledTaskEditorDraft?> {
        Binding(
            get: { viewModel.pendingEditorDraft },
            set: { draft in
                if draft == nil {
                    viewModel.dismissEditor()
                }
            }
        )
    }
}

private struct ScheduledTasksEmptyState: View {
    let filter: ScheduledTasksFilter
    let onCreate: () -> Void

    var body: some View {
        EmptyStateView(
            icon: "clock",
            heading: heading,
            subtext: subtext,
            actions: filter == .all
                ? [.init(title: "New Scheduled Task", systemImage: "plus", style: .primary, action: onCreate)]
                : [],
            iconToHeadingSpacing: 16
        )
        .frame(minHeight: 360)
    }

    private var heading: String {
        switch filter {
        case .all:
            "No scheduled tasks"
        case .active:
            "No active scheduled tasks"
        case .paused:
            "No paused scheduled tasks"
        }
    }

    private var subtext: String {
        switch filter {
        case .all:
            "Schedule recurring or one-time work."
        case .active:
            "Active schedules will appear here."
        case .paused:
            "Paused and blocked schedules will appear here."
        }
    }
}
