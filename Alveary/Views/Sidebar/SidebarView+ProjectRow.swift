import SwiftUI

struct SidebarProjectRow: View {
    static let horizontalPadding: CGFloat = 6
    static let leadingIconWidth: CGFloat = 16
    static let leadingIconFontSize: CGFloat = 11
    static let leadingSpacing: CGFloat = 10
    static let projectNameLeadingInset: CGFloat = horizontalPadding + leadingIconWidth + leadingSpacing

    let project: Project
    let isExpanded: Bool
    let isSelected: Bool
    let onToggleExpanded: () -> Void
    let onActivate: () -> Void
    let onCreateThread: () -> Void

    @State private var isHovering = false
    @State private var isHoveringCreateThread = false

    var body: some View {
        HStack(spacing: Self.leadingSpacing) {
            Button(action: onToggleExpanded) {
                Image(systemName: "folder")
                    .font(.system(size: Self.leadingIconFontSize, weight: .medium))
                    .foregroundStyle(subtleForegroundColor)
                    .frame(width: Self.leadingIconWidth, height: Self.leadingIconWidth)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(toggleAccessibilityLabel)

            ZStack(alignment: .trailing) {
                Button(action: onActivate) {
                    HStack {
                        Text(project.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(subtleForegroundColor)
                            .lineLimit(1)

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
                .help("New Thread (\(KeyboardShortcut.newThread.displayString))")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, Self.horizontalPadding)
        .background {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture(perform: onActivate)
        }
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

    private var subtleForegroundColor: Color {
        Color.primary.opacity(isSelected ? 0.76 : 0.62)
    }

    private var toggleAccessibilityLabel: String {
        isExpanded ? "Collapse \(project.name)" : "Expand \(project.name)"
    }
}
