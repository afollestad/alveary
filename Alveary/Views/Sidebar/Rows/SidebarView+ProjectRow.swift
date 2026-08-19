import SwiftUI

struct SidebarProjectRow: View, Equatable {
    static let horizontalPadding: CGFloat = 6
    static let leadingIconWidth: CGFloat = 16
    static let leadingIconFontSize: CGFloat = 11
    static let leadingSpacing: CGFloat = 8
    private static let titleClusterVerticalOffset: CGFloat = 0.5
    static let trailingActionButtonSize: CGFloat = 24
    static let trailingActionHorizontalOffset: CGFloat = 4
    static let trailingActionCenterTrailingInset = horizontalPadding + trailingActionButtonSize / 2 - trailingActionHorizontalOffset
    static let projectNameLeadingInset: CGFloat = horizontalPadding + leadingIconWidth + leadingSpacing

    /// The name alone, never the `Project` model: this row re-renders from its own hover `@State`
    /// while `List` animates a removed row out — the same window where `SidebarThreadRow`'s
    /// persisted-property read used to trap (see `SidebarThreadRowPresentation`) — and a
    /// nonisolated `==` may not read a live model either.
    let projectName: String
    let isExpanded: Bool
    let isSelected: Bool
    /// True only while this row is collapsed over a thread waiting on the user.
    /// `sidebarWaitingAttention(...)` folds nothing for an expanded project, so the dot renders on
    /// this flag alone rather than re-reading `isExpanded`.
    let hidesWaitingThread: Bool
    let suppressHoverAffordances: Bool
    let dragConfiguration: SidebarRowDragConfiguration?
    let onToggleExpanded: () -> Void
    let onActivate: () -> Void
    let onCreateThread: () -> Void

    @State private var isHovering = false
    @State private var isHoveringCreateThread = false

    init(
        projectName: String,
        isExpanded: Bool,
        isSelected: Bool,
        hidesWaitingThread: Bool = false,
        suppressHoverAffordances: Bool = false,
        dragConfiguration: SidebarRowDragConfiguration? = nil,
        initialRowHover: Bool = false,
        onToggleExpanded: @escaping () -> Void,
        onActivate: @escaping () -> Void,
        onCreateThread: @escaping () -> Void
    ) {
        self.projectName = projectName
        self.isExpanded = isExpanded
        self.isSelected = isSelected
        self.hidesWaitingThread = hidesWaitingThread
        self.suppressHoverAffordances = suppressHoverAffordances
        self.dragConfiguration = dragConfiguration
        self.onToggleExpanded = onToggleExpanded
        self.onActivate = onActivate
        self.onCreateThread = onCreateThread
        _isHovering = State(initialValue: initialRowHover)
    }

    /// The three closures are excluded: each captures the live project — context-unique for the
    /// row's stable `ForEach` identity — plus the sidebar's `@State`-backed action paths, so a
    /// captured copy cannot serve staler than a fresh one. `dragConfiguration` compares its own
    /// non-closure fields, `logicalOrder` included.
    nonisolated static func == (lhs: SidebarProjectRow, rhs: SidebarProjectRow) -> Bool {
        lhs.projectName == rhs.projectName
            && lhs.isExpanded == rhs.isExpanded
            && lhs.isSelected == rhs.isSelected
            && lhs.hidesWaitingThread == rhs.hidesWaitingThread
            && lhs.suppressHoverAffordances == rhs.suppressHoverAffordances
            && lhs.dragConfiguration == rhs.dragConfiguration
    }

    var body: some View {
        HStack(spacing: Self.leadingSpacing) {
            Button {
                withAnimation(SidebarDisclosureCaretMetrics.toggleAnimation) {
                    onToggleExpanded()
                }
            } label: {
                sidebarIcon(systemName: "folder")
                    .frame(width: Self.leadingIconWidth, height: Self.leadingIconWidth)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(toggleAccessibilityLabel)

            HStack(spacing: 0) {
                activationArea
                createThreadButton
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
    }

    private var projectForegroundColor: Color { .primary }

    private var activationArea: some View {
        Button(action: onActivate) {
            HStack(spacing: SidebarDisclosureCaretMetrics.spacing) {
                Text(projectName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(projectForegroundColor)
                    .lineLimit(1)

                SidebarDisclosureCaret(
                    isExpanded: isExpanded,
                    isRowHovering: isHovering,
                    suppressHoverAffordances: suppressHoverAffordances,
                    toggle: nil
                )

                if hidesWaitingThread {
                    SidebarWaitingAttentionDot()
                }

                Spacer(minLength: 0)
            }
            .frame(height: SidebarRowMetrics.topLevelAndThreadContentHeight, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(y: Self.titleClusterVerticalOffset)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sidebarDragSource(dragConfiguration)
        .accessibilityLabel(
            sidebarWaitingAttentionAccessibilityLabel(projectName, hidesWaitingThread: hidesWaitingThread)
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Text("New Thread")) {
            onCreateThread()
        }
    }

    private var createThreadButton: some View {
        Button(action: onCreateThread) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary.opacity(isHoveringCreateThread ? 0.95 : 0.8))
                .frame(width: Self.trailingActionButtonSize, height: Self.trailingActionButtonSize)
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
        .accessibilityHidden(true)
        .help("New Thread (\(KeyboardShortcut.newThread.displayString))")
    }

    private var showsCreateThreadButton: Bool {
        isHovering && !suppressHoverAffordances
    }

    private func sidebarIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: Self.leadingIconFontSize, weight: .medium))
            .foregroundStyle(projectForegroundColor)
    }

    private var toggleAccessibilityLabel: String {
        isExpanded ? "Collapse \(projectName)" : "Expand \(projectName)"
    }
}
