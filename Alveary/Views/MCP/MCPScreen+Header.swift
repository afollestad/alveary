import SwiftUI

struct MCPScreenHeader: View {
    @Binding var searchQuery: String
    let onRefresh: () -> Void
    let onAddServer: () -> Void

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
