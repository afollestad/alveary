import SwiftUI

struct DiffPreviewRenameSummary: View {
    let oldPath: String
    let newPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Renamed file", systemImage: "arrow.left.arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: oldPath)
                Image(systemName: "arrow.down")
                    .foregroundStyle(.secondary)
                Text(verbatim: newPath)
            }
            .font(.system(.caption, design: .monospaced))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}
