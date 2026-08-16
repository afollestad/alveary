import SwiftUI

struct ScheduledTasksScreen: View {
    let viewModel: ScheduledTasksViewModel

    @State private var deleteConfirmation: DestructiveConfirmationRequest?
    @State private var gridColumnCount = 2
    @FocusState private var focusedPaneTriggerID: String?

    private let contentVerticalPadding: CGFloat = 28
    /// Matches the new-thread hero's optical center. The offset moves a *centered* block, so
    /// each stacked suggestion below the heading pushes the icon up by half its height: this
    /// is the sibling screens' -91 plus that correction. Retune it from the empty-state
    /// snapshots whenever the cards' height or count changes.
    private let emptyStateVerticalOffset: CGFloat = -12

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
            let suggestions = viewModel.firstTaskSuggestions

            GeometryReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        if visibleTasks.isEmpty {
                            ScheduledTasksEmptyState(
                                filter: selectedFilter,
                                suggestions: suggestions,
                                onSelectSuggestion: { suggestion in
                                    viewModel.requestCreate(
                                        from: suggestion,
                                        focusRestorationID: Self.suggestionFocusID(suggestion)
                                    )
                                },
                                suggestionFocus: $focusedPaneTriggerID
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
                .restoresScrollOffset(viewModel.listScrollOffset, token: viewModel.selectedFilter)
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

    /// Shared by the card that opens a pane and by `visiblePaneTriggerFocusIDs`, which has
    /// to name the same control for dismissal to return focus to it.
    static func suggestionFocusID(_ suggestion: ScheduledTaskSuggestion) -> String {
        "scheduled-suggestion-\(suggestion.id)"
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
            ids.formUnion(viewModel.firstTaskSuggestions.map(Self.suggestionFocusID))
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

/// Suggestions stand in for the create button the other filters never had: the header's own
/// create action is always there for a blank task, so a button here would only duplicate it,
/// while a first-time user has no idea what a scheduled task is *for*.
private struct ScheduledTasksEmptyState: View {
    let filter: ScheduledTasksFilter
    let suggestions: [ScheduledTaskSuggestion]
    let onSelectSuggestion: (ScheduledTaskSuggestion) -> Void
    let suggestionFocus: FocusState<String?>.Binding

    /// Sits on the subtext's own column so the heading, subtext, and cards read as one block
    /// rather than a stack that widens with the window.
    private let suggestionMaximumWidth: CGFloat = 420

    var body: some View {
        EmptyStateView(
            icon: "clock",
            heading: heading,
            subtext: subtext,
            actions: [],
            iconToHeadingSpacing: 16
        ) {
            if filter == .all {
                suggestionStack
                    .padding(.top, 24)
            }
        }
        .frame(minHeight: 360)
    }

    /// Always stacked, never reflowed into a row: side by side, the three cards spread the
    /// heading's own block across the full pane and stop reading as one group under it.
    private var suggestionStack: some View {
        VStack(spacing: 8) {
            ForEach(suggestions) { suggestion in
                ScheduledTaskSuggestionCard(
                    suggestion: suggestion,
                    onSelect: { onSelectSuggestion(suggestion) },
                    cardFocus: suggestionFocus,
                    cardFocusID: ScheduledTasksScreen.suggestionFocusID(suggestion)
                )
                .equatable()
            }
        }
        .frame(maxWidth: suggestionMaximumWidth)
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
