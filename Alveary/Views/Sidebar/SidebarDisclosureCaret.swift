import SwiftUI

/// Metrics shared by every sidebar disclosure caret, so project rows and section headers keep the
/// same glyph size, gap after the title, and toggle timing.
enum SidebarDisclosureCaretMetrics {
    // Scaled against `SidebarProjectRow`'s leading folder icon — an 11pt glyph in a 16pt slot,
    // 10pt from the title — so the caret reads as its trailing counterpart rather than a speck.
    // Subtlety comes from the weight and colour below, not from shrinking it.
    static let spacing: CGFloat = 6
    static let width: CGFloat = 14
    static let fontSize: CGFloat = 10
    // Widens the caret's click target to reach the title gap without changing its drawn size.
    static let hitInset: CGFloat = 4
    static let flashNanoseconds: UInt64 = 900_000_000
    static let toggleAnimation: Animation = .easeInOut(duration: 0.12)
}

/// The inline expand/collapse chevron drawn after a sidebar row's title.
///
/// It owns its flash state, so every caller gets the unattended-toggle acknowledgment for free and
/// supplies only its own row's hover and drag-suppression state.
struct SidebarDisclosureCaret: View {
    let isExpanded: Bool
    let isRowHovering: Bool
    let suppressHoverAffordances: Bool
    /// `nil` draws the caret as a state indicator only: no tap, no tooltip, no hit testing at all.
    let toggle: SidebarDisclosureCaretToggle?

    @State private var isFlashing = false
    @State private var flashTask: Task<Void, Never>?

    var body: some View {
        toggleBehavior(caretGlyph)
            .accessibilityHidden(true)
            .animation(SidebarDisclosureCaretMetrics.toggleAnimation, value: isExpanded)
            .onChange(of: isExpanded) { _, _ in
                flashIfUnattended()
            }
            .onDisappear {
                flashTask?.cancel()
            }
    }

    private var caretGlyph: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: SidebarDisclosureCaretMetrics.fontSize, weight: .regular))
            // Quieter than the row title it trails: the caret is an affordance, and a collapsed
            // row now shows it permanently, so it has to sit behind the name rather than beside it.
            .foregroundStyle(.tertiary)
            .frame(width: SidebarDisclosureCaretMetrics.width, height: SidebarDisclosureCaretMetrics.width)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.86)
    }

    @ViewBuilder
    private func toggleBehavior(_ content: some View) -> some View {
        if let toggle {
            content
                // The tap has to outrank any enclosing activation `Button`, and
                // `sidebarDragSource`'s 3pt-minimum drag still wins once the pointer moves, so a
                // caret drag stays a row drag.
                .contentShape(Rectangle().inset(by: -SidebarDisclosureCaretMetrics.hitInset))
                .highPriorityGesture(
                    TapGesture().onEnded {
                        withAnimation(SidebarDisclosureCaretMetrics.toggleAnimation) {
                            toggle.action()
                        }
                    }
                )
                // An invisible caret must never swallow the row's own click.
                .allowsHitTesting(isVisible)
                .help(toggle.label)
        } else {
            // Inert even while drawn, so a click on it lands on whatever the row put underneath.
            content.allowsHitTesting(false)
        }
    }

    private var isVisible: Bool {
        sidebarDisclosureCaretIsVisible(
            isExpanded: isExpanded,
            isHovering: isRowHovering,
            isFlashing: isFlashing,
            suppressHoverAffordances: suppressHoverAffordances
        )
    }

    /// Acknowledges an expansion change the pointer did not drive, so keyboard and programmatic
    /// toggles are not silent. Restarting cancels any flash still in flight, or a rapid sequence of
    /// toggles would let the first timer hide the caret out from under the last one.
    private func flashIfUnattended() {
        guard sidebarDisclosureCaretFlashesOnExpansionChange(
            isHovering: isRowHovering,
            suppressHoverAffordances: suppressHoverAffordances
        ) else {
            return
        }

        flashTask?.cancel()
        withAnimation(SidebarDisclosureCaretMetrics.toggleAnimation) {
            isFlashing = true
        }

        flashTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: SidebarDisclosureCaretMetrics.flashNanoseconds)
            guard !Task.isCancelled else {
                return
            }

            withAnimation(SidebarDisclosureCaretMetrics.toggleAnimation) {
                isFlashing = false
            }
        }
    }
}

/// The tap a caret carries. Section headers supply one; project rows do not, because their caret
/// sits inside the activation `Button` that opens the project and the leading folder button already
/// owns the toggle.
struct SidebarDisclosureCaretToggle {
    let label: String
    let action: () -> Void
}

/// A collapsed row always shows its caret: it is the only sign that the row hides content, and
/// hiding it once the pointer left made a collapsed row indistinguishable from a childless one.
/// Drag suppression does not reach that case — the caret is state there, not hover chrome, and
/// every toggle path is drag-guarded, so a caret visible mid-drag is inert.
///
/// On an expanded row, hover and the post-toggle flash are independent reasons to show it, drag
/// suppression outranks both, and visibility drives hit testing, so a suppressed caret cannot take
/// a click.
func sidebarDisclosureCaretIsVisible(
    isExpanded: Bool,
    isHovering: Bool,
    isFlashing: Bool,
    suppressHoverAffordances: Bool
) -> Bool {
    guard isExpanded else {
        return true
    }
    return (isHovering || isFlashing) && !suppressHoverAffordances
}

/// Whether an expansion change should flash the caret into view. On an expanded row the caret is a
/// hover affordance, so a keyboard or programmatic toggle would otherwise change the row with no
/// acknowledgment at all; a pointer-driven toggle already has it on screen, and a drag suppresses
/// the whole class.
func sidebarDisclosureCaretFlashesOnExpansionChange(isHovering: Bool, suppressHoverAffordances: Bool) -> Bool {
    !isHovering && !suppressHoverAffordances
}
