import SwiftUI

struct ArchivedScreenHeader: View {
    @Binding var searchQuery: String
    @Binding var projectFilter: ArchivedProjectFilter
    let filterOptions: [ArchivedProjectFilter]
    let filterLabel: (ArchivedProjectFilter) -> String

    var body: some View {
        CompactSearchPaneHeader("Search archived threads", searchQuery: $searchQuery) {
            projectFilterMenu
        }
    }

    private var projectFilterMenu: some View {
        Menu {
            ForEach(filterOptions, id: \.self) { option in
                Button {
                    projectFilter = option
                } label: {
                    if option == projectFilter {
                        Label(filterLabel(option), systemImage: "checkmark")
                    } else {
                        Text(filterLabel(option))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(filterLabel(projectFilter))
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .menuStyle(.button)
        .secondaryActionButtonStyle()
        .fixedSize(horizontal: true, vertical: false)
        .disabled(filterOptions.count <= 1)
        .accessibilityLabel("Filter by project")
        .accessibilityValue(filterLabel(projectFilter))
    }
}
