import SwiftUI

struct MCPIntroCard: View {
    let onAddServer: () -> Void

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "server.rack")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect external tools via MCP")
                        .font(.headline)

                    Text("MCP servers give your agents access to databases, APIs, and other tools.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onAddServer) {
                    Label("Add Server", systemImage: "plus")
                }
                .primaryActionButtonStyle()
            }
        }
    }
}
