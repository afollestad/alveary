import SwiftUI

struct PullRequestsScreenHeader: View {
    @Bindable var viewModel: PullRequestsViewModel

    @State private var isFilterPopoverPresented = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(PullRequestsFilter.allCases) { filter in
                    PullRequestFilterChip(
                        filter: filter,
                        isSelected: viewModel.selectedFilter == filter,
                        onSelect: { viewModel.selectFilter(filter) }
                    )
                }
            }
            .padding(.leading, PaneHeaderLayout.leadingInset)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Pull request filter")
            .accessibilityValue(viewModel.selectedFilter.rawValue)

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                AppTextField("Search pull requests", text: $viewModel.searchQuery)
                    .frame(width: 220)

                // The 30pt icon-button frames carry ~8pt of empty slack around their
                // glyphs, and the search field's solid edge optically needs more air
                // than glyph-to-glyph spacing does. Zero spacing inside the cluster is
                // the tightest non-overlapping arrangement (~15pt glyph gap against
                // ~18pt from the field edge).
                HStack(spacing: 0) {
                    refreshButton

                    filterButton
                }
            }
        }
        .padding(.trailing, PaneHeaderLayout.trailingInset)
        .padding(.vertical, 14)
        .frame(height: PaneHeaderLayout.height)
        .background(.bar)
        .overlay(alignment: .bottom) {
            AppSeparatorHairline(surface: .paneHeader)
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

private struct PullRequestFilterChip: View {
    let filter: PullRequestsFilter
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Text(filter.rawValue)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(TabChipButtonStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
