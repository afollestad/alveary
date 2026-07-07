import SwiftUI

struct AppUpdateDownloadProgressAccessory: View {
    let progress: Double

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var percentText: String {
        clampedProgress.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                bar
                percentLabel
            }

            VStack(alignment: .trailing, spacing: 3) {
                percentLabel
                bar
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Download progress")
        .accessibilityValue(percentText)
    }

    private var bar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.22))
                Capsule()
                    .fill(AppAccentFill.primary)
                    .frame(width: max(0, proxy.size.width * clampedProgress))
            }
        }
        .frame(width: 132, height: 5)
    }

    private var percentLabel: some View {
        Text(percentText)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 36, alignment: .trailing)
    }
}
