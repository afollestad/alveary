import SwiftUI

/// Selectable capsule chip with a leading status dot, markdown-aware label, and a
/// trailing `×` close button. Used as the canonical shape for conversation tabs and
/// terminal session chips so the two surfaces stay pixel-identical — extracting the
/// shared structure prevents the two from drifting on padding, accessibility traits,
/// or chip-color rules.
///
/// The label renders through `AppMarkdownInlineLabel`, whose inline-code chip fill
/// is always `.standard` (the chip color does not track selection). See the
/// **Accent Color Surfaces** bullet in `Alveary/Views/Components/AGENTS.md` for the
/// rationale — keeping the chip uniform across selection avoids a distracting color
/// shift as the user moves selection across tabs.
struct SelectableTabChip: View {
    let displayName: String
    let statusColor: Color
    let isSelected: Bool
    let selectAccessibilityLabel: String
    let closeAccessibilityLabel: String
    var selectShortcut: KeyboardShortcut?
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
            onClose: onClose
        )
    }

    private var selectButton: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

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
        onClose: @escaping () -> Void,
        showsCloseButton: Bool = true
    ) -> some View {
        ZStack(alignment: .trailing) {
            self
            if showsCloseButton {
                tabChipCloseButton(accessibilityLabel: closeAccessibilityLabel, action: onClose)
                    .padding(.trailing, 12)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private func tabChipCloseButton(
    accessibilityLabel: String,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Image(systemName: "xmark")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(4)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focusEffectDisabled()
    .accessibilityLabel(accessibilityLabel)
}
