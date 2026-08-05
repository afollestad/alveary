import SwiftUI

struct SkillsScreenHeader: View {
    @Binding var searchQuery: String
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onCreate: () -> Void
    var createFocus: FocusState<String?>.Binding?
    var createFocusID = "skills-new"

    var body: some View {
        ResponsivePaneHeader(
            search: PaneHeaderSearch(placeholder: "Search skills", text: $searchQuery)
        ) { isCompact in
            createButton(isCompact: isCompact)

            PaneRefreshIconButton(isRefreshing: isRefreshing, action: onRefresh)
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
            .help("New Skill")
            .accessibilityLabel("New Skill")
        } else {
            Button(action: onCreate) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("New Skill")
                }
            }
            .primaryActionButtonStyle()
            .accessibilityLabel("New Skill")
        }
    }
}
