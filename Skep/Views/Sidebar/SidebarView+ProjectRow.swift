import SwiftUI

struct SidebarProjectRow: View {
    let project: Project
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onCreateThread: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleExpanded) {
                Image(systemName: leadingSymbolName)
                    .font(leadingSymbolFont)
                    .foregroundStyle(Color.primary)
                    .frame(width: 16, height: 16, alignment: .leading)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.headline)

                Text(project.baseRef ?? project.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onCreateThread) {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .animation(.easeInOut(duration: 0.12), value: isHovering)
            .help("New Thread")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleExpanded)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }

    private var leadingSymbolName: String {
        isHovering ? (isExpanded ? "chevron.down" : "chevron.right") : "folder"
    }

    private var leadingSymbolFont: Font {
        isHovering ? .caption.weight(.semibold) : .body
    }
}
