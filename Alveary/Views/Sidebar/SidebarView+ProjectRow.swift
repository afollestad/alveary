import SwiftUI

struct SidebarProjectRow: View {
    static let horizontalPadding: CGFloat = 6
    static let leadingIconWidth: CGFloat = 16
    static let leadingIconFontSize: CGFloat = 11
    static let leadingSpacing: CGFloat = 10
    private static let disclosureCaretSpacing: CGFloat = 4
    private static let disclosureCaretWidth: CGFloat = 12
    private static let disclosureCaretFontSize: CGFloat = 9
    // Widens the caret's click target to reach the title gap without changing its drawn size.
    private static let disclosureCaretHitInset: CGFloat = 4
    private static let disclosureCaretFlashNanoseconds: UInt64 = 900_000_000
    private static let titleClusterVerticalOffset: CGFloat = 0.5
    static let trailingActionButtonSize: CGFloat = 24
    static let trailingActionHorizontalOffset: CGFloat = 4
    static let trailingActionCenterTrailingInset = horizontalPadding + trailingActionButtonSize / 2 - trailingActionHorizontalOffset
    static let projectNameLeadingInset: CGFloat = horizontalPadding + leadingIconWidth + leadingSpacing

    let project: Project
    let isExpanded: Bool
    let isSelected: Bool
    let suppressHoverAffordances: Bool
    let dragConfiguration: SidebarRowDragConfiguration?
    let onToggleExpanded: () -> Void
    let onActivate: () -> Void
    let onCreateThread: () -> Void

    @State private var isHovering = false
    @State private var isHoveringCreateThread = false
    @State private var isFlashingDisclosureCaret = false
    @State private var disclosureCaretFlashTask: Task<Void, Never>?

    init(
        project: Project,
        isExpanded: Bool,
        isSelected: Bool,
        suppressHoverAffordances: Bool = false,
        dragConfiguration: SidebarRowDragConfiguration? = nil,
        initialRowHover: Bool = false,
        onToggleExpanded: @escaping () -> Void,
        onActivate: @escaping () -> Void,
        onCreateThread: @escaping () -> Void
    ) {
        self.project = project
        self.isExpanded = isExpanded
        self.isSelected = isSelected
        self.suppressHoverAffordances = suppressHoverAffordances
        self.dragConfiguration = dragConfiguration
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
        .onChange(of: isExpanded) { _, _ in
            flashDisclosureCaretIfUnattended()
        }
        .onDisappear {
            disclosureCaretFlashTask?.cancel()
        }
    }

    /// Acknowledges an expansion change the pointer did not drive, so keyboard and programmatic
    /// toggles are not silent. Restarting cancels any flash still in flight, or a rapid sequence of
    /// toggles would let the first timer hide the caret out from under the last one.
    private func flashDisclosureCaretIfUnattended() {
        guard sidebarProjectCaretFlashesOnExpansionChange(
            isHovering: isHovering,
            suppressHoverAffordances: suppressHoverAffordances
        ) else {
            return
        }

        disclosureCaretFlashTask?.cancel()
        withAnimation(.easeInOut(duration: 0.12)) {
            isFlashingDisclosureCaret = true
        }

        disclosureCaretFlashTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.disclosureCaretFlashNanoseconds)
            guard !Task.isCancelled else {
                return
            }

            withAnimation(.easeInOut(duration: 0.12)) {
                isFlashingDisclosureCaret = false
            }
        }
    }

    private var projectForegroundColor: Color { .primary }

    private var activationArea: some View {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sidebarDragSource(dragConfiguration)
        .accessibilityLabel(project.name)
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

    private var disclosureCaret: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: Self.disclosureCaretFontSize, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: Self.disclosureCaretWidth, height: Self.disclosureCaretWidth)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .opacity(showsDisclosureCaret ? 1 : 0)
            .scaleEffect(showsDisclosureCaret ? 1 : 0.86)
            // Toggling from the caret matches the leading folder button. The tap has to outrank the
            // enclosing activation `Button`, and `sidebarDragSource`'s 3pt-minimum drag still wins
            // once the pointer moves, so a caret drag stays a project drag.
            .contentShape(Rectangle().inset(by: -Self.disclosureCaretHitInset))
            .highPriorityGesture(
                TapGesture().onEnded {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        onToggleExpanded()
                    }
                }
            )
            // An invisible caret must never swallow an activation click.
            .allowsHitTesting(showsDisclosureCaret)
            .help(toggleAccessibilityLabel)
            .accessibilityHidden(true)
            .animation(.easeInOut(duration: 0.12), value: isExpanded)
    }

    private var showsDisclosureCaret: Bool {
        sidebarProjectDisclosureCaretIsVisible(
            isHovering: isHovering,
            isFlashing: isFlashingDisclosureCaret,
            suppressHoverAffordances: suppressHoverAffordances
        )
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

/// Whether an expansion change should flash the caret into view. The caret is a hover affordance,
/// so a keyboard or programmatic toggle would otherwise change the row with no acknowledgment at
/// all; a pointer-driven toggle already has it on screen, and a drag suppresses the whole class.
func sidebarProjectCaretFlashesOnExpansionChange(isHovering: Bool, suppressHoverAffordances: Bool) -> Bool {
    !isHovering && !suppressHoverAffordances
}

/// Hover and the post-toggle flash are independent reasons to show the caret. Drag suppression
/// outranks both, and visibility drives hit testing, so a suppressed caret cannot take a click.
func sidebarProjectDisclosureCaretIsVisible(
    isHovering: Bool,
    isFlashing: Bool,
    suppressHoverAffordances: Bool
) -> Bool {
    (isHovering || isFlashing) && !suppressHoverAffordances
}
