import SwiftUI

struct MCPScreenHeader: View {
    @Binding var searchQuery: String
    let onRefresh: () -> Void
    let onAddServer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MCP")
                        .font(.largeTitle.weight(.semibold))

                    Text("Connect your agents with external data sources and tools.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .secondaryActionButtonStyle()

                Button(action: onAddServer) {
                    Label("Add Server", systemImage: "plus")
                }
                .primaryActionButtonStyle()
            }

            AppTextField("Search servers", text: $searchQuery)
        }
    }
}
