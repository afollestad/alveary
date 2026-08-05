import SwiftUI

struct ArchivedScreenHeader: View {
    @Binding var searchQuery: String
    @Binding var projectFilter: ArchivedProjectFilter
    let filterOptions: [ArchivedProjectFilter]
    let filterLabel: (ArchivedProjectFilter) -> String

    var body: some View {
        ResponsivePaneHeader(
            search: PaneHeaderSearch(placeholder: "Search archived threads", text: $searchQuery)
        ) { isCompact in
            projectFilterMenu(isCompact: isCompact)
        }
    }

    private func projectFilterMenu(isCompact: Bool) -> some View {
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
                    .truncationMode(.tail)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .menuStyle(.button)
        .secondaryActionButtonStyle()
        // A project name has no bounded length, so the label is always capped and always
        // truncates. Sizing it to content pushes the search field off the pane — at any
        // width, given a long enough name, not only in a squeezed one.
        //
        // Trailing-aligned because the cap is a reservation, not the pill's width: a short
        // name leaves slack inside the frame, and centred or leading it lands as a gap
        // between the pill and the header's trailing inset.
        .frame(
            maxWidth: isCompact ? Self.compactMenuMaximumWidth : Self.menuMaximumWidth,
            alignment: .trailing
        )
        .disabled(filterOptions.count <= 1)
        .accessibilityLabel("Filter by project")
        .accessibilityValue(filterLabel(projectFilter))
    }

    private static let menuMaximumWidth: CGFloat = 320
    private static let compactMenuMaximumWidth: CGFloat = 220
}
