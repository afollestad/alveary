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
        ResponsivePaneHeader(
            filter: PaneHeaderFilter(
                options: ScheduledTasksFilter.allCases,
                selection: $selectedFilter,
                title: \.rawValue,
                accessibilityLabel: "Scheduled task filter"
            )
        ) { isCompact in
            createButton(isCompact: isCompact)
        }
    }

    @ViewBuilder
    private func createButton(isCompact: Bool) -> some View {
        if let createFocus {
            createButtonContent(isCompact: isCompact)
                .focused(createFocus, equals: createFocusID)
        } else {
            createButtonContent(isCompact: isCompact)
        }
    }

    @ViewBuilder
    private func createButtonContent(isCompact: Bool) -> some View {
        if isCompact {
            Button(action: onCreate) {
                Image(systemName: "plus")
            }
            .iconActionButtonStyle()
            .help("New Scheduled Task")
            .accessibilityLabel("New Scheduled Task")
        } else {
            Button(action: onCreate) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("New Scheduled Task")
                }
            }
            .primaryActionButtonStyle()
            .accessibilityLabel("New Scheduled Task")
        }
    }
}
