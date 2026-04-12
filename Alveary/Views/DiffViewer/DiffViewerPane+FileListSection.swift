import SwiftUI

struct DiffViewerFileListSection: View {
    let files: [FileStatus]
    let isGitRepository: Bool
    let isSelected: (FileStatus) -> Bool
    let fileDisplayName: (FileStatus) -> String
    let statusSymbol: (FileStatus) -> String
    let onSelectFile: (FileStatus) -> Void
    let onStageFile: (FileStatus) -> Void
    let onUnstageFile: (FileStatus) -> Void
    let onDiscardFile: (FileStatus) -> Void

    var body: some View {
        List(files) { file in
            Button {
                onSelectFile(file)
            } label: {
                HStack(spacing: 10) {
                    Text(statusSymbol(file))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(file.isStaged ? .green : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(fileDisplayName(file))
                            .lineLimit(1)
                            .foregroundStyle(.primary)

                        Text(file.isStaged ? "Staged" : "Unstaged")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityAddTraits(isSelected(file) ? .isSelected : [])
            }
            .buttonStyle(.plain)
            .appSelectionRowBackground(isSelected: isSelected(file))
            .contextMenu {
                if file.isStaged {
                    Button("Unstage") {
                        onUnstageFile(file)
                    }
                } else {
                    Button("Stage") {
                        onStageFile(file)
                    }
                }

                Button("Discard", role: .destructive) {
                    onDiscardFile(file)
                }
            }
        }
        .overlay {
            if files.isEmpty {
                if isGitRepository {
                    EmptyStateView(
                        icon: "checkmark.circle",
                        heading: "Working tree is clean",
                        subtext: "There are no local changes to preview right now.",
                        actions: []
                    )
                } else {
                    EmptyStateView(
                        icon: "tray",
                        heading: "Git features unavailable",
                        subtext: "This project is not a Git repository, so there are no Git diffs to show.",
                        actions: []
                    )
                }
            }
        }
    }
}
