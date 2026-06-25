import SwiftUI

struct SidebarProjectsHeaderRow: View {
    static let contentLeadingPadding: CGFloat = 8

    private static let actionButtonSize: CGFloat = 24
    private static let trailingPadding: CGFloat = 16

    @State private var isHoveringAddProject = false

    let onAddProject: () -> Void

    var body: some View {
        HStack {
            Text("Projects")
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button(action: onAddProject) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary.opacity(isHoveringAddProject ? 0.95 : 0.8))
                    .frame(width: Self.actionButtonSize, height: Self.actionButtonSize)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(isHoveringAddProject ? 0.12 : 0))
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .onHover { isHovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHoveringAddProject = isHovering
                }
            }
            .accessibilityLabel("Add Project")
            .help("Add Project... (\(KeyboardShortcut.addProject.displayString))")
        }
        .padding(.leading, Self.contentLeadingPadding)
        .padding(.trailing, Self.trailingPadding)
        .padding(.top, SidebarRowMetrics.pinnedThreadBoundarySpacing)
        .padding(.bottom, 8)
    }
}
