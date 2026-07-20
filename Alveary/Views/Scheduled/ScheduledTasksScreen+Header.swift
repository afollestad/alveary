import SwiftUI

struct ScheduledTasksScreenHeader: View {
    @Binding var selectedFilter: ScheduledTasksFilter
    let onCreate: () -> Void
    var createFocus: FocusState<String?>.Binding?
    var createFocusID: String

    init(
        selectedFilter: Binding<ScheduledTasksFilter>,
        onCreate: @escaping () -> Void,
        createFocus: FocusState<String?>.Binding? = nil,
        createFocusID: String = "scheduled-new"
    ) {
        _selectedFilter = selectedFilter
        self.onCreate = onCreate
        self.createFocus = createFocus
        self.createFocusID = createFocusID
    }

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

            createButton
        }
        .padding(.trailing, 21)
        .padding(.vertical, 14)
        .background(.bar)
        .overlay(alignment: .bottom) {
            AppSeparatorHairline(surface: .paneHeader)
        }
    }

    @ViewBuilder
    private var createButton: some View {
        if let createFocus {
            createButtonContent
                .focused(createFocus, equals: createFocusID)
        } else {
            createButtonContent
        }
    }

    private var createButtonContent: some View {
        Button(action: onCreate) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text("New Scheduled Task")
            }
        }
        .primaryActionButtonStyle()
        .accessibilityLabel("New Scheduled Task")
        .padding(.leading, 12)
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
