import SwiftUI

/// Capsule button style shared by conversation tab chips and terminal session chips.
/// Fills the whole capsule as a hit area so taps anywhere — not just on the text —
/// trigger the select action, and animates a pressed fill for press feedback.
struct TabChipButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .contentShape(Capsule(style: .continuous))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return AppSelectionStyle.pressedFill
        }
        if isSelected {
            return AppSelectionStyle.rowFill
        }
        return Color.secondary.opacity(0.08)
    }
}
