import SwiftUI

enum TabChipStatusIndicator {
    case dot(Color)
    case spinner(Color)
}

/// Selectable capsule chip with a leading status dot, markdown-aware label, and a
/// trailing `×` close button. Used as the canonical shape for conversation tabs and
/// terminal session chips so the two surfaces stay pixel-identical — extracting the
/// shared structure prevents the two from drifting on padding, accessibility traits,
/// or chip-color rules.
///
/// The label renders through `AppMarkdownInlineLabel`, whose inline-code chip fill
/// is always `.standard`; chip color does not track selection. See
/// `Alveary/Views/Components/TabChips/AGENTS.md`.
struct SelectableTabChip: View {
    private static let statusIndicatorSize: CGFloat = 8

    let displayName: String
    let statusIndicator: TabChipStatusIndicator
    let isSelected: Bool
    let selectAccessibilityLabel: String
    let closeAccessibilityLabel: String
    var selectShortcut: KeyboardShortcut?
    /// Optional tooltip text for the trailing `×` close button. Conversation tabs
    /// pass `"Close Conversation (⌘W)"` here; terminal session chips leave it nil
    /// because terminal close has no modifier-key shortcut yet. Nil suppresses the
    /// `.help(...)` modifier entirely so SwiftUI doesn't render an empty tooltip.
    var closeHelpText: String?
    /// Optional "Rename" custom accessibility action attached to the select button
    /// (surfaced via the VoiceOver rotor). Set by surfaces that support inline rename
    /// — conversation tabs do; terminal session chips do not. Routing this through
    /// the shared component rather than letting the caller apply its own
    /// `.accessibilityAction(named:)` on the wrapping view keeps the action bound to
    /// the select button's accessibility element instead of the outer container,
    /// which otherwise hides the action from users navigating by individual element.
    var renameAccessibilityAction: (() -> Void)?
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        selectButton.tabChipShell(
            closeAccessibilityLabel: closeAccessibilityLabel,
            closeHelpText: closeHelpText,
            onClose: onClose
        )
    }

    private var selectButton: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                TabChipStatusIndicatorView(indicator: statusIndicator)
                    .frame(width: Self.statusIndicatorSize, height: Self.statusIndicatorSize)

                AppMarkdownInlineLabel(text: displayName)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .tabChipContentLayout()
        }
        .buttonStyle(TabChipButtonStyle(isSelected: isSelected))
        .focusEffectDisabled()
        .accessibilityLabel(selectAccessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityActions {
            if let renameAccessibilityAction {
                Button("Rename...", action: renameAccessibilityAction)
            }
        }
        .keyboardShortcut(selectShortcut)
    }
}

struct TabChipStatusIndicatorView: View {
    let indicator: TabChipStatusIndicator

    var body: some View {
        switch indicator {
        case .dot(let color):
            Circle()
                .fill(color)
        case .spinner(let color):
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.5)
                .tint(color)
        }
    }
}

extension View {
    /// Applies the shared tab-chip inner padding. Used by the selectable variant
    /// (`SelectableTabChip.selectButton`) and the editing variant
    /// (`ConversationTabChip.editingChip`) so the two branches cannot drift on
    /// padding values — toggling between display and rename must not resize the chip.
    func tabChipContentLayout() -> some View {
        padding(.leading, 12)
            .padding(.vertical, 8)
            .padding(.trailing, 36)
    }

    /// Wraps `self` in the shared tab-chip outer shell: a trailing-aligned ZStack
    /// with the standard `×` close button overlaid on the right edge, plus a
    /// `.fixedSize` so the chip hugs its content. Both the selectable and editing
    /// variants of a tab chip use this so the outer geometry stays identical.
    ///
    /// Pass `showsCloseButton: false` to suppress the `×` while keeping the same
    /// trailing dead-space from `.tabChipContentLayout()` — this keeps the chip's
    /// overall width consistent between modes, so toggling into rename doesn't
    /// resize the chip. Editing mode hides the `×` so users don't have to guess
    /// whether clicking it commits, cancels, or deletes the conversation.
    func tabChipShell(
        closeAccessibilityLabel: String,
        closeHelpText: String? = nil,
        onClose: @escaping () -> Void,
        showsCloseButton: Bool = true
    ) -> some View {
        ZStack(alignment: .trailing) {
            self
            if showsCloseButton {
                TabChipCloseButton(
                    accessibilityLabel: closeAccessibilityLabel,
                    helpText: closeHelpText,
                    action: onClose
                )
                .padding(.trailing, 12)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Shared trailing `×` affordance for `SelectableTabChip` and the
/// `ConversationTabChip` editing variant. Extracted into a view (rather than a
/// free function) so it can track its own `@State` hover state and lighten the
/// icon / draw a subtle circular background on hover, matching the
/// `SidebarProjectsHeaderRow` +-button treatment for parity across surfaces.
private struct TabChipCloseButton: View {
    let accessibilityLabel: String
    let helpText: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary.opacity(isHovering ? 1 : 0.8))
                .padding(4)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(isHovering ? 0.12 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(accessibilityLabel)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .modifier(OptionalHelp(text: helpText))
    }
}

/// Applies `.help(text)` only when `text` is non-nil. A plain `.help(text ?? "")`
/// would hand SwiftUI an empty tooltip string, which on macOS renders an
/// empty-looking popover after the hover delay.
private struct OptionalHelp: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text {
            content.help(text)
        } else {
            content
        }
    }
}
