import SwiftUI

struct PullRequestsScreenHeader: View {
    @Bindable var viewModel: PullRequestsViewModel

    @State private var isFilterPopoverPresented = false

    var body: some View {
        ResponsivePaneHeader(
            filter: PaneHeaderFilter(
                options: PullRequestsFilter.allCases,
                selection: Binding(
                    get: { viewModel.selectedFilter },
                    set: { viewModel.selectFilter($0) }
                ),
                title: \.rawValue,
                accessibilityLabel: "Pull request filter"
            ),
            search: PaneHeaderSearch(
                placeholder: "Search pull requests",
                text: $viewModel.searchQuery,
                maximumWidth: 220
            ),
            // Both glyphs here are wide marks inside their 30pt frames, so zero box
            // spacing already reads as the ~15pt glyph gap the shared default buys a
            // narrow `plus`. See `PaneHeaderLayout.actionSpacing`.
            actionSpacing: 0
        ) { _ in
            refreshButton

            filterButton
        }
    }

    private var refreshButton: some View {
        PaneRefreshIconButton(
            isRefreshing: viewModel.isRefreshing,
            accessibilityLabel: "Refresh pull requests"
        ) {
            viewModel.requestRefresh()
        }
    }

    private var filterButton: some View {
        // A popover, not a `Menu`: both filter groups are multi-select, and a menu
        // would dismiss on the first click.
        Button {
            isFilterPopoverPresented.toggle()
        } label: {
            Image(systemName: filterButtonSymbolName)
        }
        .iconActionButtonStyle()
        .help("Filter pull requests")
        .accessibilityLabel("Filter pull requests")
        .accessibilityValue(filterAccessibilityValue)
        .popover(isPresented: $isFilterPopoverPresented, arrowEdge: .bottom) {
            PullRequestsFilterPopover(viewModel: viewModel)
        }
    }

    private var filterButtonSymbolName: String {
        viewModel.hasActiveMenuFilters
            ? "line.3.horizontal.decrease.circle.fill"
            : "line.3.horizontal.decrease.circle"
    }

    private var filterAccessibilityValue: String {
        let statuses = viewModel.selectedStatuses.isEmpty
            ? "All statuses"
            : viewModel.selectedStatuses.map(\.filterLabel).sorted().joined(separator: ", ")
        let repositories = viewModel.selectedRepositories.isEmpty
            ? "All repositories"
            : viewModel.selectedRepositories.sorted().joined(separator: ", ")
        return "\(statuses); \(repositories)"
    }
}
