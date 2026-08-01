import SwiftUI

/// Octicons do not size by font, so the branch glyph states its own box; this
/// matches the optical weight of the adjacent SF Symbols at the button's size.
private let diffBranchMenuOcticonSize: CGFloat = 17

/// The branch chooser shared by the commit and create-pull-request modals:
/// base branch, the checked-out branch when it differs, and "+ New branch".
/// Hosts own selection state and which options are selectable.
struct DiffBranchSelectionMenu: View {
    let baseBranch: String
    let currentBranch: String?
    let selectedTitle: String
    let isBaseSelectable: Bool
    let isCurrentSelectable: Bool
    let isDisabled: Bool
    let accessibilityLabel: String
    let onSelectBase: () -> Void
    let onSelectCurrent: () -> Void
    let onSelectNew: () -> Void

    var body: some View {
        Menu {
            Button(baseBranch, action: onSelectBase)
                .disabled(!isBaseSelectable)

            if isCurrentSelectable, let currentBranch {
                Button(currentBranch, action: onSelectCurrent)
            }

            Button("+ New branch", action: onSelectNew)
        } label: {
            HStack(spacing: 8) {
                OcticonImage(name: "GitBranchOcticon", size: diffBranchMenuOcticonSize)
                    .foregroundStyle(.secondary)

                Text(selectedTitle)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(selectedTitle)
    }
}
