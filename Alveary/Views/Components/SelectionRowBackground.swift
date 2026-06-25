import AppKit
import SwiftUI

struct AppSelectionRowBackground: View {
    let isSelected: Bool
    let isPressed: Bool
    let isHovered: Bool
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
            .fill(fillColor)
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
            .animation(.easeOut(duration: 0.22), value: isPressed)
            .animation(.easeOut(duration: 0.08), value: isSelected)
    }

    private var fillColor: Color {
        if isPressed {
            return AppSelectionRowFill.pressed
        } else if isSelected {
            return AppAccentFill.primary
        } else if isHovered {
            return AppSelectionRowFill.hovered
        } else {
            return .clear
        }
    }
}

private enum AppSelectionRowFill {
    static let hovered: Color = Color.secondary.opacity(0.08)

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
    let selectionBackgroundLeadingInset: CGFloat
    let selectionBackgroundTrailingInset: CGFloat
    let selectionBackgroundTopInset: CGFloat
    let selectionBackgroundBottomInset: CGFloat
    let showsHoverBackground: Bool
    let action: () -> Void

    // Using a single `DragGesture(minimumDistance: 0)` for both press tracking and the
    // click action because SwiftUI's `TapGesture`/`onTapGesture` on macOS stops firing when
    // a click is held past its short-click threshold — the press-highlight background
    // shows up on mouse-down but mouse-up after a long hold goes unrecognized.
    // `DragGesture.onEnded` fires on mouse-up regardless of hold duration, and we gate the
    // action on a small translation so it still reads as a click, not a drag-release.
    @State private var isPressed = false
    @State private var isHovered = false
    @State private var isSelectionPending = false
    @State private var wasSelectedOnPress = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(rowPressGesture)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction { action() }
            .listRowBackground(selectionRowBackground)
            .onDisappear {
                resetTransientState()
            }
            .onHover { isHovered in
                guard showsHoverBackground else {
                    return
                }
                withAnimation(.easeOut(duration: 0.12)) {
                    self.isHovered = isHovered
                }
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

    private var rowPressGesture: some Gesture {
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
    }

    private var selectionRowBackground: some View {
        AppSelectionRowBackground(
            isSelected: isSelected || isSelectionPending,
            isPressed: isPressed,
            isHovered: showsHoverBackground && isHovered,
            leadingInset: selectionBackgroundLeadingInset,
            trailingInset: selectionBackgroundTrailingInset,
            topInset: selectionBackgroundTopInset,
            bottomInset: selectionBackgroundBottomInset
        )
    }

    private func resetTransientState() {
        isPressed = false
        isHovered = false
        isSelectionPending = false
        wasSelectedOnPress = false
    }
}

private struct SelectionRowBackgroundModifier: ViewModifier {
    let isSelected: Bool
    let isHovered: Bool
    let showsHoverBackground: Bool
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat

    @State private var isPointerInside = false

    func body(content: Content) -> some View {
        content
            .listRowBackground(
                AppSelectionRowBackground(
                    isSelected: isSelected,
                    isPressed: false,
                    isHovered: isHovered || (showsHoverBackground && isPointerInside),
                    leadingInset: leadingInset,
                    trailingInset: trailingInset,
                    topInset: topInset,
                    bottomInset: bottomInset
                )
            )
            .onHover { hovering in
                guard showsHoverBackground else {
                    return
                }
                withAnimation(.easeOut(duration: 0.12)) {
                    isPointerInside = hovering
                }
            }
            .onDisappear {
                isPointerInside = false
            }
    }
}

extension View {
    func appSelectionRowBackground(
        isSelected: Bool,
        isHovered: Bool = false,
        showsHoverBackground: Bool = false,
        leadingInset: CGFloat = 10,
        trailingInset: CGFloat = 10,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 0
    ) -> some View {
        modifier(SelectionRowBackgroundModifier(
            isSelected: isSelected,
            isHovered: isHovered,
            showsHoverBackground: showsHoverBackground,
            leadingInset: leadingInset,
            trailingInset: trailingInset,
            topInset: topInset,
            bottomInset: bottomInset
        ))
    }

    /// Combines `contentShape`, tap gesture with press feedback, accessibility
    /// selection traits, and `appSelectionRowBackground` into a single modifier
    /// so every selectable list row behaves consistently.
    func appSelectableRow(
        isSelected: Bool,
        identity: AnyHashable? = nil,
        selectionBackgroundLeadingInset: CGFloat = 10,
        selectionBackgroundTrailingInset: CGFloat = 10,
        selectionBackgroundTopInset: CGFloat = 0,
        selectionBackgroundBottomInset: CGFloat = 0,
        showsHoverBackground: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        modifier(SelectableRowModifier(
            isSelected: isSelected,
            identity: identity,
            selectionBackgroundLeadingInset: selectionBackgroundLeadingInset,
            selectionBackgroundTrailingInset: selectionBackgroundTrailingInset,
            selectionBackgroundTopInset: selectionBackgroundTopInset,
            selectionBackgroundBottomInset: selectionBackgroundBottomInset,
            showsHoverBackground: showsHoverBackground,
            action: action
        ))
    }
}
