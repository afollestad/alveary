import SwiftUI

let appHeaderTogglePressedOpacity = 0.78
let appExpansionAnimationDuration: TimeInterval = 0.22
let appExpansionAnimation: Animation = .easeInOut(duration: appExpansionAnimationDuration)

extension View {
    /// Pins expandable-row subtree reflow to the shared expansion easing for a
    /// specific value change. Pair with `withAnimation(appExpansionAnimation)`.
    func appExpansionAnimationOverride<Value: Equatable>(value: Value) -> some View {
        transaction(value: value) { transaction in
            transaction.animation = appExpansionAnimation
        }
    }
}
