import SwiftUI

struct SidebarProjectRow: View {
    static let horizontalPadding: CGFloat = 6
    static let leadingIconWidth: CGFloat = 16
    static let leadingIconFontSize: CGFloat = 11
    static let leadingSpacing: CGFloat = 10
    private static let disclosureCaretSpacing: CGFloat = 4
    private static let disclosureCaretWidth: CGFloat = 12
    private static let disclosureCaretFontSize: CGFloat = 9
    private static let titleClusterVerticalOffset: CGFloat = 0.5
    static let trailingActionHorizontalOffset: CGFloat = 4
    static let projectNameLeadingInset: CGFloat = horizontalPadding + leadingIconWidth + leadingSpacing

    let project: Project
    let isExpanded: Bool
    let isSelected: Bool
    let onToggleExpanded: () -> Void
    let onActivate: () -> Void
    let onCreateThread: () -> Void

    @State private var isHovering = false
    @State private var isHoveringCreateThread = false

    init(
        project: Project,
        isExpanded: Bool,
        isSelected: Bool,
        initialRowHover: Bool = false,
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
    }

    var body: some View {
        HStack(spacing: Self.leadingSpacing) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    onToggleExpanded()
                }
            } label: {
                sidebarIcon(systemName: "folder")
                    .frame(width: Self.leadingIconWidth, height: Self.leadingIconWidth)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(toggleAccessibilityLabel)

            ZStack(alignment: .trailing) {
                Button(action: onActivate) {
                    HStack(spacing: Self.disclosureCaretSpacing) {
                        Text(project.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(projectForegroundColor)
                            .lineLimit(1)

                        disclosureCaret

                        Spacer(minLength: 0)
                    }
                    .frame(height: SidebarRowMetrics.topLevelAndThreadContentHeight, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(y: Self.titleClusterVerticalOffset)
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

    private var showsCreateThreadButton: Bool {
        isHovering || isSelected
    }

    private var disclosureCaret: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: Self.disclosureCaretFontSize, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: Self.disclosureCaretWidth, height: Self.disclosureCaretWidth)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .opacity(isHovering ? 1 : 0)
            .scaleEffect(isHovering ? 1 : 0.86)
            .accessibilityHidden(true)
            .animation(.easeInOut(duration: 0.12), value: isExpanded)
    }

    private func sidebarIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: Self.leadingIconFontSize, weight: .medium))
            .foregroundStyle(projectForegroundColor)
    }

    private var toggleAccessibilityLabel: String {
        isExpanded ? "Collapse \(project.name)" : "Expand \(project.name)"
    }
}
