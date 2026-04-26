import SwiftUI

struct SettingsValueStepper: View {
    let title: String
    let range: ClosedRange<Int>

    @Binding private var value: Int

    init(
        _ title: String,
        value: Binding<Int>,
        in range: ClosedRange<Int>
    ) {
        self.title = title
        _value = value
        self.range = range
    }

    var body: some View {
        HStack(spacing: 0) {
            stepButton(systemImage: "minus", accessibilityLabel: "Decrease \(title)", action: decrement)
                .disabled(value <= range.lowerBound)

            Text("\(value) pt")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            stepButton(systemImage: "plus", accessibilityLabel: "Increase \(title)", action: increment)
                .disabled(value >= range.upperBound)
        }
        .padding(4)
        .frame(
            minWidth: SettingsScreenLayout.settingsValueStepperWidth,
            maxWidth: .infinity,
            minHeight: SettingsScreenLayout.settingsControlSurfaceHeight,
            maxHeight: SettingsScreenLayout.settingsControlSurfaceHeight
        )
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.14))
        )
        .frame(maxWidth: .infinity)
        // Treat the pair of buttons as one adjustable value for VoiceOver.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value) points")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                increment()
            case .decrement:
                decrement()
            @unknown default:
                break
            }
        }
    }

    private func stepButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 30, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(SettingsValueStepperButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }

    private func increment() {
        value = min(value + 1, range.upperBound)
    }

    private func decrement() {
        value = max(value - 1, range.lowerBound)
    }
}

private struct SettingsValueStepperButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary.opacity(isEnabled ? 0.9 : 0.35))
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed && isEnabled ? 0.08 : 0))
            )
    }
}
