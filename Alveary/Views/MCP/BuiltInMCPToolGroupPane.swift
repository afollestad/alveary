import SwiftUI

/// Read-only details for one feature's `alveary_host` tools. There is nothing to edit or
/// submit, so the pane carries no footer and reads no session; the header's close is its
/// only action.
struct BuiltInMCPToolGroupPane: View, Equatable {
    let group: BuiltInMCPToolGroup
    let onDismiss: () -> Void

    /// `onDismiss` is excluded for the reason `MCPPane` gives.
    nonisolated static func == (lhs: BuiltInMCPToolGroupPane, rhs: BuiltInMCPToolGroupPane) -> Bool {
        lhs.group == rhs.group
    }

    var body: some View {
        VStack(spacing: 0) {
            ContextualPaneHeader(
                group.title,
                closeAccessibilityLabel: "Close built-in tools",
                onClose: onDismiss
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(
                        "Alveary offers these tools to the agent in every conversation, alongside the MCP servers "
                            + "you add. They cannot be edited or removed."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    ForEach(group.tools) { tool in
                        BuiltInMCPToolDetails(tool: tool)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(ContextualPaneLayout.contentInsets())
            }
        }
        .onExitCommand(perform: onDismiss)
    }
}

private struct BuiltInMCPToolDetails: View {
    let tool: BuiltInMCPTool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(tool.title)
                    .font(.headline)

                Spacer(minLength: 8)

                // Fixed so a long title wraps instead of squeezing the capsule.
                MCPMetaCapsule(tool.isReadOnly ? "Read-only" : "Can make changes")
                    .fixedSize()
            }

            // The name the agent calls, so a transcript's tool row and this list match up.
            Text(tool.name)
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)

            // The catalog writes this for the model, so it reads as instructions; that is
            // exactly what tells the user when the agent will reach for the tool.
            Text(tool.description)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }
}
