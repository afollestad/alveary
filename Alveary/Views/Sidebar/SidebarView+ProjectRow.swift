import SwiftUI

struct SidebarProjectRow: View {
    static let horizontalPadding: CGFloat = 6
    static let leadingIconWidth: CGFloat = 16
    static let leadingIconFontSize: CGFloat = 11
    static let leadingSpacing: CGFloat = 10
    static let trailingActionHorizontalOffset: CGFloat = 4
    static let projectNameLeadingInset: CGFloat = horizontalPadding + leadingIconWidth + leadingSpacing

    let project: Project
    let isExpanded: Bool
    let isSelected: Bool
    let onToggleExpanded: () -> Void
    let onActivate: () -> Void
    let onCreateThread: () -> Void

    @State private var isHovering = false
    @State private var isHoveringToggleIcon = false
    @State private var isHoveringCreateThread = false

    init(
        project: Project,
        isExpanded: Bool,
        isSelected: Bool,
        initialRowHover: Bool = false,
        initialToggleIconHover: Bool = false,
        onToggleExpanded: @escaping () -> Void,
        onActivate: @escaping () -> Void,
        onCreateThread: @escaping () -> Void
    ) {
        self.project = project
        self.isExpanded = isExpanded
        self.isSelected = isSelected
        self.onToggleExpanded = onToggleExpanded
        self.onActivate = onActivate
        self.onCreateThread = onCreateThread
        _isHovering = State(initialValue: initialRowHover)
        _isHoveringToggleIcon = State(initialValue: initialToggleIconHover)
    }

    var body: some View {
        HStack(spacing: Self.leadingSpacing) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    onToggleExpanded()
                }
            } label: {
                ZStack {
                    toggleIcon(systemName: "folder")
                        .opacity(showsExpansionIcon ? 0 : 1)
                        .scaleEffect(showsExpansionIcon ? 0.86 : 1)

                    toggleIcon(systemName: "chevron.right")
                        .opacity(showsExpansionIcon && !isExpanded ? 1 : 0)
                        .scaleEffect(showsExpansionIcon && !isExpanded ? 1 : 0.86)

                    toggleIcon(systemName: "chevron.down")
                        .opacity(showsExpansionIcon && isExpanded ? 1 : 0)
                        .scaleEffect(showsExpansionIcon && isExpanded ? 1 : 0.86)
                }
                .frame(width: Self.leadingIconWidth, height: Self.leadingIconWidth)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(toggleAccessibilityLabel)
            .onHover { isHovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHoveringToggleIcon = isHovering
                }
            }
            .animation(.easeInOut(duration: 0.12), value: isExpanded)

            ZStack(alignment: .trailing) {
                Button(action: onActivate) {
                    HStack {
                        Text(project.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(projectForegroundColor)
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
                .offset(x: Self.trailingActionHorizontalOffset)
                .opacity(showsCreateThreadButton ? 1 : 0)
                .allowsHitTesting(showsCreateThreadButton)
                .onHover { isHovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isHoveringCreateThread = isHovering
                    }
                }
                .animation(.easeInOut(duration: 0.12), value: isHovering)
                .accessibilityLabel("New Thread")
                .accessibilityHidden(!showsCreateThreadButton)
                .help("New Thread (\(KeyboardShortcut.newThread.displayString))")
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: SidebarRowMetrics.topLevelAndThreadContentHeight, alignment: .center)
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
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }

    private var projectForegroundColor: Color { .primary }

    private var showsExpansionIcon: Bool {
        isHoveringToggleIcon
    }

    private var showsCreateThreadButton: Bool {
        isHovering || isSelected
    }

    private func toggleIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: Self.leadingIconFontSize, weight: .medium))
            .foregroundStyle(projectForegroundColor)
    }

    private var toggleAccessibilityLabel: String {
        isExpanded ? "Collapse \(project.name)" : "Expand \(project.name)"
    }
}
