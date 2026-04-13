import SwiftUI

struct SidebarProjectRow: View {
    let project: Project
    let isExpanded: Bool
    let isSelected: Bool
    let isActive: Bool
    let onToggleExpanded: () -> Void
    let onActivate: () -> Void
    let onCreateThread: () -> Void

    @State private var isHovering = false
    @State private var isHoveringCreateThread = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleExpanded) {
                Image(systemName: leadingSymbolName)
                    .font(leadingSymbolFont)
                    .foregroundStyle(Color.primary)
                    .frame(width: 16, height: 16)
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary.opacity(isHoveringCreateThread ? 0.95 : 0.8))
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(isHoveringCreateThread ? 0.12 : 0))
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .offset(x: 4)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .onHover { isHovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isHoveringCreateThread = isHovering
                    }
                }
                .animation(.easeInOut(duration: 0.12), value: isHovering)
                .accessibilityLabel("New Thread")
                .help("Create a new thread")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .onHover { isHovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                self.isHovering = isHovering

                if !isHovering {
                    isHoveringCreateThread = false
                }
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }

    private var showDisclosure: Bool {
        isHovering || isActive
    }

    private var leadingSymbolName: String {
        showDisclosure ? disclosureSymbolName : "folder"
    }

    private var leadingSymbolFont: Font {
        showDisclosure ? .caption.weight(.semibold) : .body
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
