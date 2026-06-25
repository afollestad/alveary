import SwiftUI

struct SidebarSectionHeaderRow: View {
    static let contentLeadingPadding: CGFloat = 8

    private static let actionButtonSize: CGFloat = 24
    private static let actionIconSize: CGFloat = 11
    private static let trailingPadding: CGFloat = 16

    @State private var isHoveringAddProject = false

    let title: String
    let onAddProject: (() -> Void)?

    init(title: String, onAddProject: (() -> Void)? = nil) {
        self.title = title
        self.onAddProject = onAddProject
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            if let onAddProject {
                Button(action: onAddProject) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: Self.actionIconSize, weight: .semibold))
                        .foregroundStyle(.primary.opacity(isHoveringAddProject ? 0.9 : 0.68))
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
            } else {
                Color.clear
                    .frame(width: Self.actionButtonSize, height: Self.actionButtonSize)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Self.contentLeadingPadding)
        .padding(.trailing, Self.trailingPadding)
        .padding(.top, SidebarRowMetrics.pinnedThreadBoundarySpacing)
        .padding(.bottom, 0)
    }
}
