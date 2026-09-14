import SwiftUI

/// Identify which source folder the settings below apply to when a project has multiple folders.
struct ProjectSettingsFolderSummary: View {
    let sourceFolder: SourceFolderSnapshot
    let isPrimary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(sourceFolder.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if isPrimary {
                    Text("Primary")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                        .fixedSize()
                }
            }
            Text(CanonicalPath.abbreviateHomeDirectory(sourceFolder.path))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(sourceFolder.path)
        }
    }
}
