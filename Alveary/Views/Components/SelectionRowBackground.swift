import SwiftUI

enum AppSelectionStyle {
    static var rowFill: Color {
        Color.accentColor.opacity(0.26)
    }

    static var pressedFill: Color {
        Color.accentColor.opacity(0.3)
    }
}

struct AppSelectionRowBackground: View {
    let isSelected: Bool
    let isPressed: Bool
    let topInset: CGFloat
    let bottomInset: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(fillColor)
            .padding(.horizontal, 10)
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
    }

    private var fillColor: Color {
        if isPressed {
            return AppSelectionStyle.pressedFill
        } else if isSelected {
            return AppSelectionStyle.rowFill
        } else {
            return .clear
        }
    }
}

private struct SelectableRowModifier: ViewModifier {
    let isSelected: Bool
    let action: () -> Void

    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .listRowBackground(
                AppSelectionRowBackground(
                    isSelected: isSelected,
                    isPressed: isPressed,
                    topInset: 0,
                    bottomInset: 0
                )
            )
    }
}

extension View {
    func appSelectionRowBackground(
        isSelected: Bool,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 0
    ) -> some View {
        listRowBackground(
            AppSelectionRowBackground(
                isSelected: isSelected,
                isPressed: false,
                topInset: topInset,
                bottomInset: bottomInset
            )
        )
    }

    /// Combines `contentShape`, tap gesture with press feedback, accessibility
    /// selection traits, and `appSelectionRowBackground` into a single modifier
    /// so every selectable list row behaves consistently.
    func appSelectableRow(
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        modifier(SelectableRowModifier(isSelected: isSelected, action: action))
    }
}
