import AppKit
import SwiftUI

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
            .animation(.easeOut(duration: 0.22), value: isPressed)
            .animation(.easeOut(duration: 0.22), value: isSelected)
    }

    private var fillColor: Color {
        if isPressed {
            return AppSelectionRowFill.pressed
        } else if isSelected {
            return AppAccentFill.primary
        } else {
            return .clear
        }
    }
}

private enum AppSelectionRowFill {
    static let pressed: Color = Color(nsColor: .accentDerived { accent, appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return accent.blended(withFraction: 0.50, of: .black) ?? accent
        default:
            return accent.blended(withFraction: 0.45, of: .white) ?? accent
        }
    })
}

private struct SelectableRowModifier: ViewModifier {
    let isSelected: Bool
    let identity: AnyHashable?
    let action: () -> Void

    // Using a single `DragGesture(minimumDistance: 0)` for both press tracking and the
    // click action because SwiftUI's `TapGesture`/`onTapGesture` on macOS stops firing when
    // a click is held past its short-click threshold — the press-highlight background
    // shows up on mouse-down but mouse-up after a long hold goes unrecognized.
    // `DragGesture.onEnded` fires on mouse-up regardless of hold duration, and we gate the
    // action on a small translation so it still reads as a click, not a drag-release.
    @State private var isPressed = false
    @State private var isSelectionPending = false
    @State private var wasSelectedOnPress = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            wasSelectedOnPress = isSelected
                            isSelectionPending = false
                            isPressed = true
                        }
                    }
                    .onEnded { value in
                        let isClick = abs(value.translation.width) < 10
                            && abs(value.translation.height) < 10
                        if isClick {
                            // Optimistically keep the released row selected until the
                            // owning model publishes, avoiding a pressed -> clear flash.
                            isSelectionPending = !wasSelectedOnPress
                            action()
                        }
                        isPressed = false
                    }
            )
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction { action() }
            .listRowBackground(
                AppSelectionRowBackground(
                    isSelected: isSelected || isSelectionPending,
                    isPressed: isPressed,
                    topInset: 0,
                    bottomInset: 0
                )
            )
            .onDisappear {
                resetTransientState()
            }
            .onChange(of: isSelected) { _, selected in
                if selected {
                    isSelectionPending = false
                } else if !isPressed {
                    isSelectionPending = false
                }
            }
            .onChange(of: identity) {
                resetTransientState()
            }
    }

    private func resetTransientState() {
        isPressed = false
        isSelectionPending = false
        wasSelectedOnPress = false
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
        identity: AnyHashable? = nil,
        action: @escaping () -> Void
    ) -> some View {
        modifier(SelectableRowModifier(isSelected: isSelected, identity: identity, action: action))
    }
}
