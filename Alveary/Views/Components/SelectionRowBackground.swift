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
    var opacity: Double = 1

    var body: some View {
        RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
            .fill(fillColor)
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
            .opacity(opacity)
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

/// The shared row fills. Internal rather than file-private because rows that draw their
/// own card must reach `pressed` to match the `List`-hosted rows' press feedback; see
/// `AppSelectableRowState`.
enum AppSelectionRowFill {
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

/// The transient interaction state `.appSelectableRow` publishes into its own content.
///
/// Rows inside a `List` read this state through `listRowBackground`; rows in a `ScrollView`
/// draw their own card, where that background never renders, and would otherwise have no
/// press feedback and no way to look selected until the owning model publishes. Reading it
/// from a child of the row's content — a `.background` view, not the row struct itself —
/// keeps a press or hover from invalidating the whole row body.
struct AppSelectableRowState: Equatable {
    var isPressed = false
    /// True between mouse-up and the model publishing the new selection.
    var isSelectionPending = false
    var isHovered = false
    /// True anywhere inside `.appSelectableRow(...)`'s content. A row that is also
    /// `.focusable()` makes `\.isFocused` report *its* focus to every descendant, so a
    /// control that draws its own focus ring from that value would ring itself whenever
    /// the row is focused. Descendants use this to tell "I am focused" from "my row is".
    var isInsideRow = false
}

private struct AppSelectableRowStateKey: EnvironmentKey {
    static let defaultValue = AppSelectableRowState()
}

extension EnvironmentValues {
    var appSelectableRowState: AppSelectableRowState {
        get { self[AppSelectableRowStateKey.self] }
        set { self[AppSelectableRowStateKey.self] = newValue }
    }
}

private struct SelectableRowModifier: ViewModifier {
    let isSelected: Bool
    let identity: AnyHashable?
    let selectionBackgroundLeadingInset: CGFloat
    let selectionBackgroundTrailingInset: CGFloat
    let selectionBackgroundTopInset: CGFloat
    let selectionBackgroundBottomInset: CGFloat
    let selectionBackgroundOpacity: Double
    let showsHoverBackground: Bool
    let suppressesPressFeedback: Bool
    let suppressesAction: Bool
    /// False for rows that draw their own card. `listRowBackground` only renders inside a `List`,
    /// so outside one the fill is a view value built per row and then discarded — pure cost on
    /// every `LazyVStack` materialization during a scroll.
    let showsListRowBackground: Bool
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
            .environment(\.appSelectableRowState, publishedRowState)
            .contentShape(Rectangle())
            .gesture(rowPressGesture)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction {
                if !suppressesAction {
                    action()
                }
            }
            .listRowBackground(showsListRowBackground ? selectionRowBackground : nil)
            .onDisappear {
                resetTransientState()
            }
            .onHover { isHovered in
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
            .onChange(of: suppressesAction) { _, suppressed in
                if suppressed {
                    resetPressState()
                }
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
                if isClick, !suppressesAction {
                    // Optimistically keep the released row selected until the
                    // owning model publishes, avoiding a pressed -> clear flash.
                    isSelectionPending = !wasSelectedOnPress
                    action()
                }
                isPressed = false
            }
    }

    /// Hover is published ungated: `showsHoverBackground` decides only whether the
    /// `List` fill draws it, and a self-drawn card makes that call for itself.
    private var publishedRowState: AppSelectableRowState {
        AppSelectableRowState(
            isPressed: !suppressesPressFeedback && isPressed,
            isSelectionPending: isSelectionPending,
            isHovered: isHovered,
            isInsideRow: true
        )
    }

    private var selectionRowBackground: some View {
        AppSelectionRowBackground(
            isSelected: isSelected || isSelectionPending,
            isPressed: !suppressesPressFeedback && isPressed,
            isHovered: showsHoverBackground && isHovered,
            leadingInset: selectionBackgroundLeadingInset,
            trailingInset: selectionBackgroundTrailingInset,
            topInset: selectionBackgroundTopInset,
            bottomInset: selectionBackgroundBottomInset,
            opacity: selectionBackgroundOpacity
        )
    }

    private func resetTransientState() {
        isHovered = false
        resetPressState()
    }

    private func resetPressState() {
        isPressed = false
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
    let opacity: Double

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
                    bottomInset: bottomInset,
                    opacity: opacity
                )
            )
            .onHover { hovering in
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
        bottomInset: CGFloat = 0,
        opacity: Double = 1
    ) -> some View {
        modifier(SelectionRowBackgroundModifier(
            isSelected: isSelected,
            isHovered: isHovered,
            showsHoverBackground: showsHoverBackground,
            leadingInset: leadingInset,
            trailingInset: trailingInset,
            topInset: topInset,
            bottomInset: bottomInset,
            opacity: opacity
        ))
    }

    /// Combines `contentShape`, tap gesture with press feedback, accessibility
    /// selection traits, and `appSelectionRowBackground` into a single modifier
    /// so every selectable list row behaves consistently.
    ///
    /// - Parameter showsListRowBackground: Pass `false` from a row that draws its own card. The
    ///   selection fill is published through `listRowBackground`, which renders only inside a
    ///   `List`, so a `ScrollView`-hosted row otherwise builds it once per materialization and
    ///   throws it away. Such rows reach press, hover, and pending-selection through
    ///   `AppSelectableRowState` instead, which this modifier still publishes either way.
    func appSelectableRow(
        isSelected: Bool,
        identity: AnyHashable? = nil,
        selectionBackgroundLeadingInset: CGFloat = 10,
        selectionBackgroundTrailingInset: CGFloat = 10,
        selectionBackgroundTopInset: CGFloat = 0,
        selectionBackgroundBottomInset: CGFloat = 0,
        selectionBackgroundOpacity: Double = 1,
        showsHoverBackground: Bool = false,
        suppressesPressFeedback: Bool = false,
        suppressesAction: Bool = false,
        showsListRowBackground: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        modifier(SelectableRowModifier(
            isSelected: isSelected,
            identity: identity,
            selectionBackgroundLeadingInset: selectionBackgroundLeadingInset,
            selectionBackgroundTrailingInset: selectionBackgroundTrailingInset,
            selectionBackgroundTopInset: selectionBackgroundTopInset,
            selectionBackgroundBottomInset: selectionBackgroundBottomInset,
            selectionBackgroundOpacity: selectionBackgroundOpacity,
            showsHoverBackground: showsHoverBackground,
            suppressesPressFeedback: suppressesPressFeedback,
            suppressesAction: suppressesAction,
            showsListRowBackground: showsListRowBackground,
            action: action
        ))
    }
}
