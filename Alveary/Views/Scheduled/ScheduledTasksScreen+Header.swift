import SwiftUI

struct ScheduledTasksScreenHeader: View {
    @Binding var selectedFilter: ScheduledTasksFilter
    let onCreate: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(ScheduledTasksFilter.allCases) { filter in
                    ScheduledTaskFilterChip(
                        filter: filter,
                        isSelected: selectedFilter == filter,
                        onSelect: { selectedFilter = filter }
                    )
                }
            }
            .padding(.leading, 20)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Scheduled task filter")
            .accessibilityValue(selectedFilter.rawValue)

            Spacer(minLength: 0)

            Button(action: onCreate) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("New scheduled task")
                }
            }
            .primaryActionButtonStyle()
            .accessibilityLabel("New scheduled task")
            .padding(.leading, 12)
        }
        .padding(.trailing, 21)
        .padding(.vertical, 14)
        .background(.bar)
        .overlay(alignment: .bottom) {
            AppSeparatorHairline(surface: .paneHeader)
        }
    }
}

private struct ScheduledTaskFilterChip: View {
    let filter: ScheduledTasksFilter
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
