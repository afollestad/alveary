import SwiftUI

private extension VerticalAlignment {
    /// Centers a row's leading glyph on its *title* rather than on the stack edge or on
    /// the whole text block. `.top` floats the glyph above the title's cap height, and
    /// `.center` would drift down as the secondary lines grow, so neither reads as the
    /// glyph belonging to the name.
    enum TitleCenter: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[VerticalAlignment.center]
        }
    }

    static let titleCenter = VerticalAlignment(TitleCenter.self)
}

struct MCPServerRow: View, Equatable {
    let server: MCPServer
    let isSelected: Bool
    let onEdit: () -> Void
    let onRemove: () -> Void
    let editFocus: FocusState<String?>.Binding
    let editFocusID: String

    /// The actions and the focus binding are excluded: the actions close over the `server`
    /// compared here plus the screen's view-model reference and its `@State` confirmation
    /// box, and the binding reads the screen's `@FocusState` storage — none of which a
    /// captured copy can serve staler than a fresh one. `isSelected` is compared because
    /// it drives the row's fill.
    nonisolated static func == (lhs: MCPServerRow, rhs: MCPServerRow) -> Bool {
        lhs.server == rhs.server
            && lhs.isSelected == rhs.isSelected
            && lhs.editFocusID == rhs.editFocusID
    }

    var body: some View {
        HStack(alignment: .titleCenter, spacing: 14) {
            Image(systemName: server.transport == .http ? "globe" : "terminal")
                .foregroundStyle(AppAccentIcon.foreground)

            VStack(alignment: .leading, spacing: 6) {
                Text(server.name)
                    .font(.headline)
                    .lineLimit(1)
                    // Projects the title's centre up through the `VStack` so the glyph
                    // and the trailing menu both align to it.
                    .alignmentGuide(.titleCenter) { $0[VerticalAlignment.center] }

                Text(server.transport == .http ? (server.url ?? "HTTP server") : (server.command ?? "stdio server"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    // Middle truncation keeps both ends of a long command path — the app
                    // bundle and the binary name — visible in a half-width grid column.
                    .truncationMode(.middle)

                if !server.providers.isEmpty {
                    Text("Agents: \(server.providers.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            AppOverflowMenu(name: "Server actions") {
                actionRows
            }
        }
        .padding(14)
        // Grid rows equalize height the same way the cards below do: content-driven,
        // filling the `LazyVGrid` row so a two-line card stays level with a three-line one.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .appSelectableCard(
            isSelected: isSelected,
            cornerRadius: 18,
            focus: editFocus,
            focusID: editFocusID,
            action: onEdit
        )
        // Outside `appSelectableCard(...)`: the right-click needs the full-card
        // `contentShape` that modifier installs.
        .contextMenu {
            actionRows
        }
        // `.contain` keeps the actions menu reachable; collapsing the row would hide it.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(server.name)
    }

    /// The row's secondary actions, filling both its three-dot menu and its right-click
    /// menu so the two cannot offer different rows. The row face itself opens the edit
    /// pane, so Edit has no row here.
    private var actionRows: some View {
        AppOverflowMenuRow(
            title: "Remove",
            systemImage: "trash",
            role: .destructive,
            action: onRemove
        )
    }
}

/// The small secondary capsule the MCP cards share — a recommended server's transport, a
/// built-in tool's feature — so the two surfaces cannot drift apart.
struct MCPMetaCapsule: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.14)))
            .foregroundStyle(.secondary)
    }
}

struct RecommendedMCPCard: View, Equatable {
    let server: RecommendedMCPServer
    let isSelected: Bool
    let onAdd: () -> Void
    let addFocus: FocusState<String?>.Binding
    let addFocusID: String

    /// The action and the focus binding are excluded, for the same reasons as
    /// `MCPServerRow`.
    nonisolated static func == (lhs: RecommendedMCPCard, rhs: RecommendedMCPCard) -> Bool {
        lhs.server == rhs.server
            && lhs.isSelected == rhs.isSelected
            && lhs.addFocusID == rhs.addFocusID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(server.template.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 8)

                // The card opens the same add pane, so this duplicates it deliberately:
                // the glyph is what makes the card look actionable at a glance.
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .iconActionButtonStyle(.inline)
                .fixedSize()
                .help("Add")
                .accessibilityLabel("Add \(server.template.name)")
            }

            MCPMetaCapsule(server.template.transport.rawValue.uppercased())

            Text(server.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        // Content-driven height filling the `LazyVGrid` row, so a one-line description
        // card stays level with a two-line one beside it. Mirrors `SkillCard`.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .appSelectableCard(
            isSelected: isSelected,
            cornerRadius: 18,
            focus: addFocus,
            focusID: addFocusID,
            action: onAdd
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(server.template.name)
    }
}
