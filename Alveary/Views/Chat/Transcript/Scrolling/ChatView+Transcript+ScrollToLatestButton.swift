import SwiftUI

struct ScrollToLatestButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .transcriptFont(.body, weight: .semibold)
                .foregroundStyle(Color.primary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(AppAccentFill.primary)
                )
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
        .accessibilityLabel("Jump to latest message")
        .help("Jump to latest message")
    }
}
