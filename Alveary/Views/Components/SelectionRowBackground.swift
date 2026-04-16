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

    // Using a single `DragGesture(minimumDistance: 0)` for both press tracking and the
    // click action because SwiftUI's `TapGesture`/`onTapGesture` on macOS stops firing when
    // a click is held past its short-click threshold — the press-highlight background
    // shows up on mouse-down but mouse-up after a long hold goes unrecognized.
    // `DragGesture.onEnded` fires on mouse-up regardless of hold duration, and we gate the
    // action on a small translation so it still reads as a click, not a drag-release.
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed { isPressed = true }
                    }
                    .onEnded { value in
                        isPressed = false
                        if abs(value.translation.width) < 10,
                           abs(value.translation.height) < 10 {
                            action()
                        }
                    }
            )
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction { action() }
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
