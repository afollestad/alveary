import SwiftUI

struct ScheduledTasksScreen: View {
    let viewModel: ScheduledTasksViewModel

    @State private var selectedFilter = ScheduledTasksFilter.all
    @State private var deleteConfirmation: ScheduledTaskRowPresentation?

    private let contentVerticalPadding: CGFloat = 28
    // Match the new-thread hero's optical center within the Scheduled pane.
    private let emptyStateVerticalOffset: CGFloat = -91

    var body: some View {
        VStack(spacing: 0) {
            ScheduledTasksScreenHeader(
                selectedFilter: $selectedFilter,
                onCreate: viewModel.requestCreate
            )

            GeometryReader { proxy in
                ScrollView {
                    let visibleTasks = viewModel.tasks(for: selectedFilter)
                    ZStack(alignment: .topLeading) {
                        if visibleTasks.isEmpty {
                            ScheduledTasksEmptyState(
                                filter: selectedFilter,
                                onCreate: viewModel.requestCreate
                            )
                            .offset(y: emptyStateVerticalOffset)
                        }

                        VStack(alignment: .leading, spacing: 24) {
                            if let errorMessage = viewModel.errorMessage {
                                InlineBanner(
                                    message: errorMessage,
                                    severity: .error,
                                    autoDismissAfter: nil,
                                    onDismiss: viewModel.clearError
                                )
                            }

                            if !visibleTasks.isEmpty {
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
                    }
                    .frame(minHeight: max(proxy.size.height - (contentVerticalPadding * 2), 0), alignment: .top)
                    .padding(
                        EdgeInsets(
                            top: contentVerticalPadding,
                            leading: 20,
                            bottom: contentVerticalPadding,
                            trailing: 28
                        )
                    )
                }
                // The fixed filters can be changed at any scroll depth; each result set starts at the top.
                .id(selectedFilter.id)
            }
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
