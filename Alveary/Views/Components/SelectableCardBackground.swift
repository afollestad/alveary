import SwiftUI

extension View {
    /// The full chrome for a grid card that is itself the click target for a contextual
    /// pane: the shared card fill, click and press handling, and keyboard focus.
    ///
    /// The pieces are bundled because their order is load-bearing and broke twice when
    /// spelled per card:
    /// - The fill sits *inside* `.appSelectableRow(...)`, which publishes press and hover
    ///   into its content — applied outside it, the background resolves the environment
    ///   from above the modifier that publishes it and never shows either.
    /// - Focus takes `.activate` interactions only, so a mouse click never hands the card
    ///   keyboard focus — with the default interactions, clicking a card focused it and
    ///   drew the system ring, which no macOS control does on click. Tab still reaches
    ///   the card under Full Keyboard Access, where Return runs `action`.
    /// - The `.focusEffect` shape sits *outside* `.focusable()` and the row modifier's own
    ///   interaction `contentShape`. Applied beneath them it is ignored, and the focus
    ///   ring hugs the card's rectangular frame instead of its rounded corners. One
    ///   `cornerRadius` feeds both the fill and the ring so the two cannot drift apart.
    ///
    /// `focusID` doubles as the row identity that resets recycled transient state: both
    /// must be stable and unique per card, so a second parameter could only disagree.
    func appSelectableCard(
        isSelected: Bool,
        cornerRadius: CGFloat,
        focus: FocusState<String?>.Binding,
        focusID: String,
        action: @escaping () -> Void
    ) -> some View {
        background(AppSelectableCardBackground(isSelected: isSelected, cornerRadius: cornerRadius))
            .appSelectableRow(isSelected: isSelected, identity: focusID, action: action)
            .focusable(interactions: .activate)
            .focused(focus, equals: focusID)
            .onKeyPress(.return) {
                action()
                return .handled
            }
            .contentShape(.focusEffect, RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// The card fill for a `.appSelectableRow(...)` row that draws its own card, which every
/// row in a `ScrollView` must: that modifier publishes its selection chrome through
/// `listRowBackground`, and outside a `List` nothing renders it.
///
/// It is a separate view rather than a computed background on the row because
/// `AppSelectableRowState` is published *into* the modified content — a row reading it on
/// itself resolves the environment from above the modifier that publishes it, so it would
/// show no press or hover and stay unselected until its model published. Reading here also
/// keeps a pointer crossing the row from invalidating the row's own `body`.
struct AppSelectableCardBackground: View {
    let isSelected: Bool
    /// Per-surface because the card shapes differ: pull-request rows are 16, the Skills
    /// and MCP cards 18.
    let cornerRadius: CGFloat

    @Environment(\.appSelectableRowState) private var rowState

    var body: some View {
        // Tint only, no opaque base: the window backdrop is a desktop-tint material that
        // shifts with wallpaper and window activation, so no flat color can sit under the
        // tint without changing the card's resting color somewhere. Grid reflows crossfade
        // (`adaptiveCardGridReflow(...)`) precisely so translucent cards never glide across
        // each other.
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
            // Matching `AppSelectionRowBackground` so self-drawn cards and `List` rows feel alike.
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
