import SwiftUI

/// The row card's fill. Split out of `PullRequestRow` so it can read
/// `AppSelectableRowState`, which `.appSelectableRow` publishes into its content and is
/// therefore invisible to the row struct that applies the modifier.
///
/// Reading press and hover here also keeps them off `PullRequestRow.body`: a mouse-down
/// or a pointer crossing the row repaints this shape alone, and the pressed frame lands
/// before the selection reaches the model.
struct PullRequestRowCardBackground: View {
    let isSelected: Bool

    @Environment(\.appSelectableRowState) private var rowState

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(fill)
            // Matching `AppSelectionRowBackground` so the two paths' rows feel alike.
            .animation(.easeOut(duration: 0.22), value: rowState.isPressed)
            .animation(.easeOut(duration: 0.08), value: isSelected)
    }

    private var fill: Color {
        if rowState.isPressed {
            return AppSelectionRowFill.pressed
        }
        // `isSelectionPending` carries the release until the model publishes.
        if isSelected || rowState.isSelectionPending {
            return AppAccentFill.primary
        }
        return Color.secondary.opacity(rowState.isHovered ? 0.12 : 0.08)
    }
}
