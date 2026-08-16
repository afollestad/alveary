import SwiftUI

struct ArchivedScreen: View {
    @Bindable var viewModel: ArchivedThreadsViewModel

    private let contentVerticalPadding: CGFloat = 28
    // Match the new-thread hero's optical center within the Archived pane.
    private let emptyStateVerticalOffset: CGFloat = -91

    var body: some View {
        VStack(spacing: 0) {
            ArchivedScreenHeader(
                searchQuery: $viewModel.searchQuery,
                projectFilter: $viewModel.projectFilter,
                filterOptions: viewModel.projectFilterOptions,
                filterLabel: viewModel.projectFilterLabel
            )

            // Resolved once per body pass rather than inside the scroll content: that
            // closure re-runs on every geometry change, so the filter/bucket/sort
            // pipeline used to run again for each frame of a window resize.
            let sections = viewModel.sections
            let busyThreadIDs = viewModel.busyThreadIDs
            let errorMessage = viewModel.errorMessage
            let hasAnyArchivedThreads = !viewModel.items.isEmpty

            GeometryReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        if sections.isEmpty {
                            ArchivedScreenEmptyState(hasAnyArchivedThreads: hasAnyArchivedThreads)
                                .offset(y: emptyStateVerticalOffset)
                        }

                        VStack(alignment: .leading, spacing: 24) {
                            if let errorMessage {
                                InlineBanner(
                                    message: errorMessage,
                                    severity: .error,
                                    autoDismissAfter: nil,
                                    onDismiss: viewModel.dismissError
                                )
                            }

                            ForEach(sections) { section in
                                ArchivedThreadSectionView(
                                    section: section,
                                    busyThreadIDs: busyThreadIDs,
                                    onRestore: viewModel.requestRestore,
                                    onDelete: viewModel.requestPermanentDeletion
                                )
                                .equatable()
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
                .restoresScrollOffset(viewModel.listScrollOffset)
            }
        }
        .task {
            viewModel.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .threadLifecycleChanged)) { notification in
            viewModel.handleThreadLifecycleChanged(notification)
        }
        .confirmationDialog(
            "Restore archived thread?",
            isPresented: Binding(
                get: { viewModel.pendingRestore != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.cancelRestore()
                    }
                }
            ),
            presenting: viewModel.pendingRestore
        ) { item in
            Button("Unarchive") {
                Task { await viewModel.confirmRestore(item) }
            }

            Button("Cancel", role: .cancel) {
                viewModel.cancelRestore()
            }
        } message: { item in
            Text(archivedThreadRestoreConfirmationMessage(title: item.title))
        }
        .confirmationDialog(
            "Delete thread permanently?",
            isPresented: Binding(
                get: { viewModel.pendingPermanentDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.cancelPermanentDeletion()
                    }
                }
            ),
            presenting: viewModel.pendingPermanentDeletion
        ) { item in
            Button("Delete", role: .destructive) {
                Task { await viewModel.confirmPermanentDeletion(item) }
            }

            Button("Cancel", role: .cancel) {
                viewModel.cancelPermanentDeletion()
            }
        } message: { item in
            Text(threadDeleteConfirmationMessage(title: item.title, isTask: item.isTask) + " This cannot be undone.")
        }
    }
}

/// One project's archived threads. The project-less group passes a `nil` title and
/// renders its rows with no heading above them.
private struct ArchivedThreadSectionView: View, Equatable {
    let section: ArchivedThreadSection
    let busyThreadIDs: Set<ArchivedThreadItem.ID>
    let onRestore: (ArchivedThreadItem) -> Void
    let onDelete: (ArchivedThreadItem) -> Void

    /// The actions are excluded: they are unapplied view-model method references, so
    /// they read through that stable reference rather than a captured copy's values.
    nonisolated static func == (lhs: ArchivedThreadSectionView, rhs: ArchivedThreadSectionView) -> Bool {
        lhs.section == rhs.section && lhs.busyThreadIDs == rhs.busyThreadIDs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title = section.title {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }

            LazyVStack(spacing: 10) {
                ForEach(section.items) { item in
                    ArchivedThreadRow(
                        item: item,
                        isBusy: busyThreadIDs.contains(item.id),
                        onRestore: { onRestore(item) },
                        onDelete: { onDelete(item) }
                    )
                    .equatable()
                }
            }
        }
    }
}

private struct ArchivedScreenEmptyState: View {
    let hasAnyArchivedThreads: Bool

    var body: some View {
        EmptyStateView(
            icon: "archivebox",
            heading: hasAnyArchivedThreads ? "No matching threads" : "No archived threads",
            subtext: hasAnyArchivedThreads
                ? "Try a different search or project filter."
                : "Threads you archive from the sidebar will appear here.",
            actions: [],
            iconToHeadingSpacing: 16
        )
        .frame(minHeight: 360)
    }
}
