import SwiftUI

struct SidebarProjectRow: View {
    let project: Project
    let isExpanded: Bool
    let isSelected: Bool
    let onToggleExpanded: () -> Void
    let onActivate: () -> Void
    let onCreateThread: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleExpanded) {
                Image(systemName: disclosureSymbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 16, height: 16, alignment: .leading)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            ZStack(alignment: .trailing) {
                Button(action: onActivate) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name)
                                .font(.headline)

                            Text(projectSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])

                Button(action: onCreateThread) {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .animation(.easeInOut(duration: 0.12), value: isHovering)
                .help("New Thread")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }

    private var disclosureSymbolName: String {
        isExpanded ? "chevron.down" : "chevron.right"
    }

    private var projectSubtitle: String {
        if project.isGitRepository {
            project.baseRef ?? project.path
        } else {
            "local"
        }
    }
}
