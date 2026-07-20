import SwiftUI

struct MCPScreenHeader: View {
    @Binding var searchQuery: String
    let onRefresh: () -> Void
    let onAddServer: () -> Void
    var addFocus: FocusState<String?>.Binding?
    var addFocusID = "mcp-add"

    var body: some View {
        CompactSearchPaneHeader("Search servers", searchQuery: $searchQuery) {
            Button(action: onRefresh) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
            }
            .secondaryActionButtonStyle()
            .accessibilityLabel("Refresh")

            addButton
        }
    }

    @ViewBuilder
    private var addButton: some View {
        if let addFocus {
            addButtonContent
                .focused(addFocus, equals: addFocusID)
        } else {
            addButtonContent
        }
    }

    private var addButtonContent: some View {
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
