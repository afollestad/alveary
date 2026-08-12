import SwiftUI

struct ScheduledTasksScreen: View {
    let viewModel: ScheduledTasksViewModel

    @State private var deleteConfirmation: DestructiveConfirmationRequest?
    @State private var gridColumnCount = 2
    @FocusState private var focusedPaneTriggerID: String?

    private let contentVerticalPadding: CGFloat = 28
    // Match the new-thread hero's optical center within the Scheduled pane.
    private let emptyStateVerticalOffset: CGFloat = -91

    var body: some View {
        VStack(spacing: 0) {
            ScheduledTasksScreenHeader(
                selectedFilter: Binding(
                    get: { viewModel.selectedFilter },
                    set: { viewModel.selectFilter($0) }
                ),
                onCreate: { openCreatePane() },
                createFocus: $focusedPaneTriggerID
            )

            // Resolved once per body pass rather than inside the scroll content: that
            // closure re-runs on every geometry change, so each row's date formatting
            // used to run again for each frame of a window or right-pane resize.
            let selectedFilter = viewModel.selectedFilter
            let visibleTasks = viewModel.tasks(for: selectedFilter)
            let errorMessage = viewModel.errorMessage
            let pendingRunNowIDs = viewModel.pendingRunNowDefinitionIDs
            let providerNames = providerDisplayNames(for: visibleTasks)
            let selectedDefinitionID = activeEditDefinitionID

            GeometryReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        if visibleTasks.isEmpty {
                            ScheduledTasksEmptyState(
                                filter: selectedFilter,
                                onCreate: {
                                    openCreatePane(focusRestorationID: "scheduled-new-empty")
                                },
                                createFocus: $focusedPaneTriggerID
                            )
                            .offset(y: emptyStateVerticalOffset)
                        }

                        VStack(alignment: .leading, spacing: 24) {
                            if let errorMessage {
                                InlineBanner(
                                    message: errorMessage,
                                    severity: .error,
                                    autoDismissAfter: nil,
                                    onDismiss: viewModel.clearError
                                )
                            }

                            if !visibleTasks.isEmpty {
                                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                                    ForEach(visibleTasks) { task in
                                        ScheduledTaskCard(
                                            task: task,
                                            providerName: providerNames[task.providerID]
                                                ?? task.providerID.capitalized,
                                            isRunNowPending: pendingRunNowIDs.contains(task.id),
                                            isSelected: task.id == selectedDefinitionID,
                                            onOpen: {
                                                viewModel.requestEdit(definitionID: task.id)
                                            },
                                            onPause: { viewModel.pause(task) },
                                            onResume: { viewModel.resume(task) },
                                            onRunNow: { viewModel.runNow(task) },
                                            onDelete: {
                                                deleteConfirmation = makeScheduledTaskDeleteConfirmation {
                                                    viewModel.delete(task)
                                                }
                                            },
                                            cardFocus: $focusedPaneTriggerID,
                                            cardFocusID: ScheduledTaskPaneTarget.edit(task.id)
                                                .defaultFocusRestorationID
                                        )
                                        .equatable()
                                    }
                                }
                                .adaptiveCardGridReflow(columnCount: gridColumnCount)
                            }
                        }
                    }
                    .frame(minHeight: max(proxy.size.height - (contentVerticalPadding * 2), 0), alignment: .top)
                    .padding(
                        EdgeInsets(
                            top: contentVerticalPadding,
                            leading: PaneHeaderLayout.leadingInset,
                            bottom: contentVerticalPadding,
                            trailing: PaneHeaderLayout.trailingInset
                        )
                    )
                }
                // The fixed filters can be changed at any scroll depth; each result set starts at the top.
                .id(viewModel.selectedFilter.id)
                // Outside the `.id` above, so the modifier's own seed state survives a chip
                // click and an unchanged width cannot replay the flip as an animation.
                .adaptiveCardGridColumnCount($gridColumnCount)
            }
        }
        .task {
            await viewModel.loadForScreen()
        }
        .onChange(of: viewModel.paneDismissalGeneration) { _, _ in
            focusedPaneTriggerID = ContextualPaneFocusRestoration.resolve(
                preferredID: viewModel.paneFocusRestorationID,
                visibleTriggerIDs: visiblePaneTriggerFocusIDs,
                fallbackID: ScheduledTaskPaneTarget.create.defaultFocusRestorationID
            )
        }
        .destructiveConfirmation($deleteConfirmation)
    }

    private var gridColumns: [GridItem] {
        AdaptiveCardGridLayout.columns(count: gridColumnCount)
    }

    /// The task whose editor pane is open, so its card can render selected. Resolved once
    /// per body pass and handed down, rather than each card asking the view model.
    private var activeEditDefinitionID: String? {
        guard case .edit(let definitionID) = viewModel.activePaneTarget else {
            return nil
        }
        return definitionID
    }

    private func openCreatePane(focusRestorationID: String? = nil) {
        viewModel.requestCreate(focusRestorationID: focusRestorationID)
    }

    /// One entry per distinct provider, resolved above the `GeometryReader` so the rows do
    /// not each re-read `providerStatuses` on every frame. The call-site fallback repeats
    /// `providerDisplayName`'s own last resort, so a miss cannot render differently.
    private func providerDisplayNames(for tasks: [ScheduledTaskRowPresentation]) -> [String: String] {
        Set(tasks.map(\.providerID)).reduce(into: [:]) { names, providerID in
            names[providerID] = viewModel.providerDisplayName(for: providerID)
        }
    }

    private var visiblePaneTriggerFocusIDs: Set<String> {
        let visibleTasks = viewModel.tasks(for: viewModel.selectedFilter)
        var ids = Set([ScheduledTaskPaneTarget.create.defaultFocusRestorationID])
        ids.formUnion(visibleTasks.map {
            ScheduledTaskPaneTarget.edit($0.id).defaultFocusRestorationID
        })
        if viewModel.selectedFilter == .all, visibleTasks.isEmpty {
            ids.insert("scheduled-new-empty")
        }
        return ids
    }
}

/// Unlike its Skills and MCP siblings, this takes no model: the copy names no task on
/// purpose, matching the dialog it replaced.
private func makeScheduledTaskDeleteConfirmation(
    confirm: @escaping () -> Void
) -> DestructiveConfirmationRequest {
    DestructiveConfirmationRequest(
        title: "Delete scheduled task?",
        message: "Future runs will stop. Existing run history and Task threads are retained.",
        confirmTitle: "Delete",
        confirm: confirm
    )
}

private struct ScheduledTasksEmptyState: View {
    let filter: ScheduledTasksFilter
    let onCreate: () -> Void
    let createFocus: FocusState<String?>.Binding

    var body: some View {
        EmptyStateView(
            icon: "clock",
            heading: heading,
            subtext: subtext,
            actions: filter == .all
                ? [
                    .init(
                        title: "New Scheduled Task",
                        systemImage: "plus",
                        style: .primary,
                        focusID: "scheduled-new-empty",
                        action: onCreate
                    )
                ]
                : [],
            actionFocus: createFocus,
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
