import SwiftUI

struct StagedContextBanner: View {
    let context: String
    let onDismiss: () -> Void

    private var summary: String {
        let firstLine = context
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Context included."

        if firstLine.count > 96 {
            return String(firstLine.prefix(93)) + "..."
        }
        return firstLine
    }

    var body: some View {
        HStack(spacing: 12) {
            Label(summary, systemImage: "paperclip")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss context")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}
