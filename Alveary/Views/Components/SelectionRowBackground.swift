import AppKit
import SwiftUI

enum AppSelectionStyle {
    /// Selection fill used behind sidebar rows, settings rows, conversation tab chips,
    /// and the user chat bubble. The fill is a scheme-aware tint of `controlAccentColor`:
    /// dark mode layers at low opacity so selections feel like a subtle accent wash over
    /// the dark window background, while light mode layers at high opacity so the fill
    /// reads as a rich amber against the white window background. Callers that place
    /// foreground content on top should use scheme-adapting colors like `Color.primary`
    /// / `NSColor.labelColor` rather than hard-coded `.white`; the rowFill is dark enough
    /// for white text only in dark mode.
    static let rowFill: Color = accentTint(darkAlpha: 0.26, lightAlpha: 0.80)

    // Pressed-state deltas are widened in light mode (0.80 → 0.95) so the press feedback
    // is actually visible against the already-saturated `rowFill`; a tighter bump like
    // 0.88 is perceptually identical to 0.80 once the accent saturates the surface. Dark
    // mode keeps a narrower bump (0.26 → 0.38) because the tint starts low enough that a
    // small alpha change is still perceptible.
    static let pressedFill: Color = accentTint(darkAlpha: 0.38, lightAlpha: 0.95)

    private static func accentTint(darkAlpha: CGFloat, lightAlpha: CGFloat) -> Color {
        Color(nsColor: .accentDerived { accent, appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua:
                return accent.withAlphaComponent(darkAlpha)
            default:
                return accent.withAlphaComponent(lightAlpha)
            }
        })
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
