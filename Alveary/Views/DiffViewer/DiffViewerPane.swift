import AppKit
import SwiftUI

struct DiffViewerPane: View {
    let viewModel: DiffViewerViewModel
    let areAgentActionsEnabled: Bool
    @Binding private var topSectionFraction: CGFloat
    let onTopSectionFractionCommit: (CGFloat) -> Void
    let onCommitRequested: () -> Void
    let onOpenPRRequested: () -> Void

    @State private var pendingDiscardFiles: [FileStatus] = []
    @State private var isManualRefreshIndicatorVisible = false
    @State private var isFileListTopDividerVisible = false

    init(
        viewModel: DiffViewerViewModel,
        areAgentActionsEnabled: Bool,
        topSectionFraction: Binding<CGFloat> = .constant(CGFloat(AppSettings.defaultDiffViewerTopSectionFraction)),
        onTopSectionFractionCommit: @escaping (CGFloat) -> Void = { _ in },
        onCommitRequested: @escaping () -> Void,
        onOpenPRRequested: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.areAgentActionsEnabled = areAgentActionsEnabled
        _topSectionFraction = topSectionFraction
        self.onTopSectionFractionCommit = onTopSectionFractionCommit
        self.onCommitRequested = onCommitRequested
        self.onOpenPRRequested = onOpenPRRequested
    }

    var body: some View {
        VStack(spacing: 0) {
            DiffViewerPaneHeader(
                activeDirectory: viewModel.activeDirectory,
                contextualAction: viewModel.contextualAction,
                selectedFiles: viewModel.selectedFiles,
                areAgentActionsEnabled: areAgentActionsEnabled,
                isRefreshing: isManualRefreshIndicatorVisible,
                showsFileListDivider: isFileListTopDividerVisible,
                onRefresh: {
                    performManualRefresh()
                },
                onCommitRequested: onCommitRequested,
                onOpenPRRequested: onOpenPRRequested,
                onViewPRRequested: { url in
                    guard let url = URL(string: url) else {
                        return
                    }
                    NSWorkspace.shared.open(url)
                },
                onStageSelectedFiles: {
                    guard let directory = viewModel.activeDirectory else {
                        return
                    }
                    let files = viewModel.selectedFiles.filter { !$0.isStaged }

                    Task {
                        await performGitAction(errorPrefix: "Stage failed") {
                            try await viewModel.stage(files: files, in: directory)
                        }
                    }
                },
                onUnstageSelectedFiles: {
                    guard let directory = viewModel.activeDirectory else {
                        return
                    }
                    let files = viewModel.selectedFiles.filter(\.isStaged)

                    Task {
                        await performGitAction(errorPrefix: "Unstage failed") {
                            try await viewModel.unstage(files: files, in: directory)
                        }
                    }
                },
                onDiscardSelectedFiles: {
                    pendingDiscardFiles = viewModel.selectedFiles
                }
            )

            if let gitError = viewModel.gitError {
                InlineBanner(message: gitError, severity: .error, autoDismissAfter: nil, onDismiss: viewModel.clearGitError)
                    .padding(12)
            }

            if viewModel.activeDirectory == nil {
                EmptyStateView(
                    icon: "rectangle.split.3x1",
                    heading: "No diff context",
                    subtext: "Select a thread to inspect project changes and diff previews.",
                    actions: []
                )
            } else {
                DiffViewerVerticalSplit(
                    splitFraction: $topSectionFraction,
                    bounds: AppSettings.supportedDiffViewerSplitRange,
                    onCommit: onTopSectionFractionCommit
                ) {
                    DiffViewerFileListSection(
                        files: viewModel.files,
                        selectedFiles: viewModel.selectedFiles,
                        isGitRepository: viewModel.isGitRepository,
                        isLoading: viewModel.isLoadingFiles,
                        isSelected: isSelected,
                        fileDisplayName: fileDisplayName,
                        statusSymbol: statusSymbol,
                        onSelectFile: { file, behavior in
                            guard let directory = viewModel.activeDirectory else {
                                return
                            }

                            guard let preparedSelection = viewModel.selectFileImmediately(file, in: directory, behavior: behavior) else {
                                return
                            }

                            Task {
                                await viewModel.loadSelectedFileDiff(preparedSelection)
                            }
                        },
                        onStageFiles: { files in
                            guard let directory = viewModel.activeDirectory else {
                                return
                            }

                            Task {
                                await performGitAction(errorPrefix: "Stage failed") {
                                    try await viewModel.stage(files: files.filter { !$0.isStaged }, in: directory)
                                }
                            }
                        },
                        onUnstageFiles: { files in
                            guard let directory = viewModel.activeDirectory else {
                                return
                            }

                            Task {
                                await performGitAction(errorPrefix: "Unstage failed") {
                                    try await viewModel.unstage(files: files.filter(\.isStaged), in: directory)
                                }
                            }
                        },
                        onDiscardFiles: { files in
                            pendingDiscardFiles = files
                        },
                        isTopDividerVisible: $isFileListTopDividerVisible
                    )
                } bottom: {
                    DiffViewerPreviewSection(
                        selectedFile: viewModel.selectedFile,
                        selectedFileCount: viewModel.selectedFiles.count,
                        parsedDiff: viewModel.parsedDiff,
                        rawDiffContent: viewModel.rawDiffContent,
                        isPending: viewModel.isSelectedDiffPending,
                        isLoading: viewModel.isLoadingSelectedDiff,
                        fileDisplayName: fileDisplayName,
                        statusTitle: statusTitle,
                        diffPreviewIdentity: diffPreviewIdentity
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .confirmationDialog(
            discardConfirmationTitle,
            isPresented: Binding(
                get: { !pendingDiscardFiles.isEmpty },
                set: { isPresented in
                    if !isPresented {
                        pendingDiscardFiles = []
                    }
                }
            )
        ) {
            Button("Discard", role: .destructive) {
                let files = pendingDiscardFiles
                let directory = viewModel.activeDirectory
                pendingDiscardFiles = []

                Task {
                    await discardPendingFiles(files: files, in: directory)
                }
            }

            Button("Cancel", role: .cancel) {
                pendingDiscardFiles = []
            }
        } message: {
            Text(discardConfirmationMessage)
        }
    }
}

private extension DiffViewerPane {
    func performManualRefresh() {
        guard !isManualRefreshIndicatorVisible else {
            return
        }

        isManualRefreshIndicatorVisible = true
        Task { @MainActor in
            async let refresh: Void = viewModel.forceRefreshActiveDiff()
            try? await Task.sleep(for: .milliseconds(500))
            await refresh
            isManualRefreshIndicatorVisible = false
        }
    }

    func discardPendingFiles(files: [FileStatus], in directory: String?) async {
        guard let directory,
              !files.isEmpty else {
            return
        }

        await performGitAction(errorPrefix: "Discard failed") {
            try await viewModel.discard(files: files, in: directory)
        }
    }

    var discardConfirmationMessage: String {
        if pendingDiscardFiles.count == 1 {
            return "This will permanently discard the selected uncommitted change."
        }
        return "This will permanently discard the selected uncommitted changes."
    }

    var discardConfirmationTitle: String {
        pendingDiscardFiles.count == 1 ? "Discard change?" : "Discard changes?"
    }

    func performGitAction(errorPrefix: String, action: () async throws -> Void) async {
        do {
            try await action()
        } catch {
            viewModel.presentGitError("\(errorPrefix): \(error.localizedDescription)")
        }
    }

    func isSelected(_ file: FileStatus) -> Bool {
        viewModel.isFileSelected(file)
    }

    func fileDisplayName(_ file: FileStatus) -> String {
        if let originalPath = file.originalPath,
           originalPath != file.path {
            return "\(originalPath) → \(file.path)"
        }
        return file.path
    }

    func statusSymbol(for file: FileStatus) -> String {
        switch file.status {
        case .modified:
            return "●"
        case .added, .untracked:
            return "+"
        case .deleted:
            return "−"
        case .renamed:
            return "→"
        case .copied:
            return "⧉"
        case .unmerged:
            return "!"
        }
    }

    func statusTitle(for status: FileStatus.Status) -> String {
        switch status {
        case .modified:
            return "Modified"
        case .added:
            return "Added"
        case .deleted:
            return "Deleted"
        case .renamed:
            return "Renamed"
        case .copied:
            return "Copied"
        case .untracked:
            return "Untracked"
        case .unmerged:
            return "Unmerged"
        }
    }

    func diffPreviewIdentity(for file: FileStatus) -> String {
        [
            file.id,
            file.originalPath ?? "",
            file.status.rawValue,
            String(viewModel.rawDiffContent.count)
        ].joined(separator: "|")
    }

}
