import SwiftUI

struct SidebarProjectsHeaderRow: View {
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
                Image(systemName: "plus.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary.opacity(isHoveringAddProject ? 0.95 : 0.8))
                    .frame(width: 24, height: 24)
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
            .help("Add a project")
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}
