import SwiftUI

/// The read-only section above the user's servers listing every `alveary_host` tool by
/// feature, so what the agent can already do inside Alveary is discoverable next to what
/// the user adds. A card opens its group's details pane; nothing here edits or removes.
struct BuiltInMCPToolsSection: View {
    let groups: [BuiltInMCPToolGroup]
    let columns: [GridItem]
    /// Resolved once per `MCPScreen` body pass rather than read per card, so a pane
    /// opening does not make every card observe `activePaneTarget` on its own.
    let selectedGroupID: String?
    let focusedPaneTrigger: FocusState<String?>.Binding
    let onOpen: (BuiltInMCPToolGroup) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Built-in")
                .font(.title3.weight(.semibold))

            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(groups) { group in
                    BuiltInMCPToolGroupCard(
                        group: group,
                        isSelected: group.id == selectedGroupID,
                        onOpen: {
                            onOpen(group)
                        },
                        openFocus: focusedPaneTrigger,
                        openFocusID: MCPPaneTarget.builtInToolGroup(group.id).defaultFocusRestorationID
                    )
                    .equatable()
                }
            }
            .adaptiveCardGridReflow(columnCount: columns.count)
        }
    }
}

struct BuiltInMCPToolGroupCard: View, Equatable {
    let group: BuiltInMCPToolGroup
    let isSelected: Bool
    let onOpen: () -> Void
    let openFocus: FocusState<String?>.Binding
    let openFocusID: String

    /// The action and the focus binding are excluded, for the same reasons as
    /// `MCPServerRow`.
    nonisolated static func == (lhs: BuiltInMCPToolGroupCard, rhs: BuiltInMCPToolGroupCard) -> Bool {
        lhs.group == rhs.group
            && lhs.isSelected == rhs.isSelected
            && lhs.openFocusID == rhs.openFocusID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 8)

                // Fixed so a long title truncates instead of squeezing the capsule.
                MCPMetaCapsule(toolCountLabel)
                    .fixedSize()
            }

            // The names the agent calls, so a transcript's tool row and this card match
            // up; two lines previews the group and the pane lists the rest.
            Text(group.tools.map(\.name).joined(separator: ", "))
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        // Content-driven height filling the `LazyVGrid` row, as the other MCP cards do.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .appSelectableCard(
            isSelected: isSelected,
            cornerRadius: 18,
            focus: openFocus,
            focusID: openFocusID,
            action: onOpen
        )
        // No `.contextMenu`: the card has no secondary actions, and the empty builder
        // that would express that suppresses the menu anyway.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(group.title)
        .accessibilityValue(toolCountLabel)
    }

    private var toolCountLabel: String {
        group.tools.count == 1 ? "1 tool" : "\(group.tools.count) tools"
    }
}
