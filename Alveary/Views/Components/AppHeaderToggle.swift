import SwiftUI

struct AppHeaderToggle<Label: View>: View {
    let action: () -> Void
    let label: Label
    let fillsWidth: Bool
    @State private var mouseActivation = AppMouseActivationCoordinator()
    @State private var isPressed = false

    init(
        fillsWidth: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.action = action
        self.fillsWidth = fillsWidth
        self.label = label()
    }

    var body: some View {
        Button(action: performAction) {
            label
                .opacity(isPressed ? appHeaderTogglePressedOpacity : 1)
                .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .overlay {
            AppMouseTarget(
                activation: mouseActivation,
                action: performAction,
                pressedChanged: { isPressed = $0 }
            )
                .frame(maxWidth: fillsWidth ? .infinity : nil, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
        .zIndex(1)
        .accessibilityElement(children: .combine)
    }

    private func performAction() {
        // Keep this as the single activation path. The AppKit fallback marks the
        // same coordinator so it can skip itself when SwiftUI handled the click.
        mouseActivation.markActivation()
        action()
    }
}
