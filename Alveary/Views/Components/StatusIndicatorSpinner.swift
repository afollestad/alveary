import SwiftUI

/// Fixed-frame ring spinner for small status slots: 8pt status-dot slots in the
/// sidebar and tab chips, and the 16pt primary-toolbar progress slot. Only
/// `rotationEffect` animates, so the spinner never relayouts mid-spin and its
/// footprint stays identical to the status dot it replaces.
///
/// Snapshot fixtures rely on the `statusSpinnerAnimationsDisabled` environment key
/// (set by the shared snapshot hosts) for a deterministic arc angle, because
/// `EnvironmentValues.accessibilityReduceMotion` is get-only and cannot be injected
/// in tests. Reduce-motion users get the same static-arc treatment via the
/// environment read.
struct StatusIndicatorSpinner: View {
    var color: Color
    var diameter: CGFloat = 8
    var lineWidth: CGFloat = 1.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.statusSpinnerAnimationsDisabled) private var animationsDisabled
    @State private var isRotating = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        // Inset by half the stroke so the ring renders fully inside the fixed frame.
        .padding(lineWidth / 2)
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(isRotating ? 360 : 0))
        .animation(
            isRotating ? .linear(duration: 0.9).repeatForever(autoreverses: false) : nil,
            value: isRotating
        )
        .onAppear {
            guard !reduceMotion, !animationsDisabled else {
                return
            }
            isRotating = true
        }
        .accessibilityHidden(true)
    }
}

private struct StatusSpinnerAnimationsDisabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Test hook: disables the spin animation so snapshot renders capture a fixed
    /// arc angle. Production code should never set this.
    var statusSpinnerAnimationsDisabled: Bool {
        get { self[StatusSpinnerAnimationsDisabledKey.self] }
        set { self[StatusSpinnerAnimationsDisabledKey.self] = newValue }
    }
}
