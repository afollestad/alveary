import AppKit
import SwiftUI

struct DiffViewerFileListSection: View {
    let files: [FileStatus]
    let selectedFiles: [FileStatus]
    let isGitRepository: Bool
    let isLoading: Bool
    let isSelected: (FileStatus) -> Bool
    let fileDisplayName: (FileStatus) -> String
    let onSelectFile: (FileStatus, DiffViewerFileSelectionBehavior) -> Void
    let onStageFiles: ([FileStatus]) -> Void
    let onUnstageFiles: ([FileStatus]) -> Void
    let onDiscardFiles: ([FileStatus]) -> Void

    @Binding var isTopDividerVisible: Bool

    @State private var verticalOffsetFromTop: CGFloat = 0

    var body: some View {
        ScrollViewReader { scrollProxy in
            List(files) { file in
                HStack(spacing: 10) {
                    Circle()
                        .fill(statusColor(for: file))
                        .frame(width: 8, height: 8)

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
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(file.path)
                .appSelectableRow(
                    isSelected: isSelected(file),
                    identity: file.id,
                    action: { onSelectFile(file, currentSelectionBehavior) }
                )
                .background {
                    DiffViewerSecondaryClickSelectionTarget {
                        if !isSelected(file) {
                            onSelectFile(file, .single)
                        }
                    }
                }
                .contextMenu {
                    let actionFiles = contextMenuFiles(for: file)
                    if actionFiles.contains(where: { !$0.isStaged }) {
                        Button("Stage") {
                            performContextMenuAction(for: file, action: onStageFiles)
                        }
                    }

                    if actionFiles.contains(where: \.isStaged) {
                        Button("Unstage") {
                            performContextMenuAction(for: file, action: onUnstageFiles)
                        }
                    }

                    Button("Discard", role: .destructive) {
                        performContextMenuAction(for: file, action: onDiscardFiles)
                    }
                }
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .contentMargins(.bottom, 4, for: .scrollContent)
            .clipped()
            .background {
                DiffViewerFileListScrollMonitor(
                    fileIDs: fileIDs,
                    verticalOffsetFromTop: $verticalOffsetFromTop
                )
            }
            .overlay {
                if isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)

                        Text("Loading changes…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if files.isEmpty {
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
            .onAppear {
                isTopDividerVisible = shouldShowTopDivider
            }
            .onChange(of: shouldShowTopDivider) { _, isVisible in
                isTopDividerVisible = isVisible
            }
            .onDisappear {
                isTopDividerVisible = false
            }
            .onChange(of: fileIDs) { _, newFileIDs in
                preserveTopPositionIfNeeded(scrollProxy: scrollProxy, fileIDs: newFileIDs)
            }
        }
    }

    private var fileIDs: [String] {
        files.map(\.id)
    }

    private func statusColor(for file: FileStatus) -> Color {
        file.isStaged ? .green : .secondary
    }

    private var shouldShowTopDivider: Bool {
        !files.isEmpty && verticalOffsetFromTop > 0.5
    }

    private var currentSelectionBehavior: DiffViewerFileSelectionBehavior {
        let flags = NSEvent.modifierFlags
        let isCommandPressed = flags.contains(.command)
        let isShiftPressed = flags.contains(.shift)

        switch (isCommandPressed, isShiftPressed) {
        case (true, true):
            return .rangeUnion
        case (true, false):
            return .toggle
        case (false, true):
            return .range
        case (false, false):
            return .single
        }
    }

    private func performContextMenuAction(
        for file: FileStatus,
        action: ([FileStatus]) -> Void
    ) {
        let actionFiles = contextMenuFiles(for: file)
        if !isSelected(file) {
            onSelectFile(file, .single)
        }
        action(actionFiles)
    }

    private func contextMenuFiles(for file: FileStatus) -> [FileStatus] {
        isSelected(file) ? selectedFiles : [file]
    }

    private func preserveTopPositionIfNeeded(
        scrollProxy: ScrollViewProxy,
        fileIDs: [String]
    ) {
        guard verticalOffsetFromTop <= 1,
              let firstFileID = fileIDs.first else {
            return
        }

        scrollToTop(scrollProxy: scrollProxy, firstFileID: firstFileID)
        DispatchQueue.main.async {
            scrollToTop(scrollProxy: scrollProxy, firstFileID: firstFileID)
        }
    }

    private func scrollToTop(scrollProxy: ScrollViewProxy, firstFileID: String) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollProxy.scrollTo(firstFileID, anchor: .top)
        }
        verticalOffsetFromTop = 0
    }
}
