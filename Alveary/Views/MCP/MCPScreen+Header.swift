import SwiftUI

struct MCPScreenHeader: View {
    @Binding var searchQuery: String
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onAddServer: () -> Void
    var addFocus: FocusState<String?>.Binding?
    var addFocusID = "mcp-add"

    var body: some View {
        ResponsivePaneHeader(
            search: PaneHeaderSearch(placeholder: "Search servers and tools", text: $searchQuery)
        ) { isCompact in
            addButton(isCompact: isCompact)

            PaneRefreshIconButton(isRefreshing: isRefreshing, action: onRefresh)
        }
    }

    @ViewBuilder
    private func addButton(isCompact: Bool) -> some View {
        if let addFocus {
            addButtonContent(isCompact: isCompact)
                .focused(addFocus, equals: addFocusID)
        } else {
            addButtonContent(isCompact: isCompact)
        }
    }

    @ViewBuilder
    private func addButtonContent(isCompact: Bool) -> some View {
        if isCompact {
            Button(action: onAddServer) {
                Image(systemName: "plus")
            }
            .iconActionButtonStyle()
            .help("Add Server")
            .accessibilityLabel("Add Server")
        } else {
            Button(action: onAddServer) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add Server")
                }
            }
            .primaryActionButtonStyle()
            .accessibilityLabel("Add Server")
        }
    }
}
