import SwiftUI

/// Multi-select status/repository filters. A popover rather than a `Menu` because
/// menus dismiss on every click; this stays open so several options can be toggled
/// in one visit.
struct PullRequestsFilterPopover: View {
    let viewModel: PullRequestsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            filterSection(title: "Status") {
                filterToggle("All", isOn: viewModel.selectedStatuses.isEmpty) {
                    viewModel.clearStatusFilters()
                }
                ForEach(PullRequestStatus.filterCases, id: \.self) { status in
                    filterToggle(status.filterLabel, isOn: viewModel.selectedStatuses.contains(status)) {
                        viewModel.toggleStatusFilter(status)
                    }
                }
            }

            filterSection(title: "Repository") {
                filterToggle("All Repositories", isOn: viewModel.selectedRepositories.isEmpty) {
                    viewModel.clearRepositoryFilters()
                }
                ForEach(viewModel.repositoryFilterOptions, id: \.self) { nameWithOwner in
                    filterToggle(nameWithOwner, isOn: viewModel.selectedRepositories.contains(nameWithOwner)) {
                        viewModel.toggleRepositoryFilter(nameWithOwner)
                    }
                }
            }
        }
        .padding(14)
        .frame(minWidth: 200, maxWidth: 320, alignment: .leading)
    }

    private func filterSection(title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            rows()
        }
    }

    /// Checkbox rows drive the view model directly; unchecking an already-empty
    /// "All" row is a no-op, so the binding ignores the incoming value.
    private func filterToggle(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: { _ in action() })) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .toggleStyle(.checkbox)
    }
}
