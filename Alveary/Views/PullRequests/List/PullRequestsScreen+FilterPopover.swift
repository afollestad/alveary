import SwiftUI

/// Single-select status plus multi-select repositories. A popover rather than a `Menu` because
/// menus dismiss on every click; the repository group stays open so several can be toggled in
/// one visit. Status is radio because it is pushed into the GitHub search, whose qualifiers only
/// AND — see `PullRequestStatusFilter`.
struct PullRequestsFilterPopover: View {
    let viewModel: PullRequestsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            filterSection(title: "Status") {
                Picker("Status", selection: statusSelection) {
                    ForEach(PullRequestStatusFilter.menuCases, id: \.self) { status in
                        Text(status.filterLabel).tag(status)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
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

    /// Writes go through `selectStatusFilter(_:)`, which persists the choice and reloads the
    /// visible tab — the selection is part of the search, not a local narrowing.
    private var statusSelection: Binding<PullRequestStatusFilter> {
        Binding(
            get: { viewModel.selectedStatusFilter },
            set: { viewModel.selectStatusFilter($0) }
        )
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
