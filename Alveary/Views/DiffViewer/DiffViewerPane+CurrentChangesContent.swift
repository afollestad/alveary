import SwiftUI

struct DiffViewerCurrentChangesContent: View {
    let viewModel: DiffViewerViewModel
    @Binding var topSectionFraction: CGFloat
    let onTopSectionFractionCommit: (CGFloat) -> Void
    @Binding var isFileListTopDividerVisible: Bool
    let fileDisplayName: (FileStatus) -> String
    let statusTitle: (FileStatus.Status) -> String
    let diffPreviewIdentity: (FileStatus) -> String
    let onPresentGitError: (String) -> Void
    let onDiscardFiles: ([FileStatus]) -> Void

    var body: some View {
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
                selectedFileID: viewModel.selectedFile?.id,
                isSelected: viewModel.isFileSelected,
                fileDisplayName: fileDisplayName,
                onSelectFile: selectFile,
                onNavigateFile: navigateFile,
                onStageFiles: stageFiles,
                onUnstageFiles: unstageFiles,
                onDiscardFiles: onDiscardFiles,
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

    private func selectFile(_ file: FileStatus, behavior: DiffViewerFileSelectionBehavior) {
        guard let directory = viewModel.activeDirectory,
              let preparedSelection = viewModel.selectFileImmediately(file, in: directory, behavior: behavior) else {
            return
        }

        Task {
            await viewModel.loadSelectedFileDiff(preparedSelection)
        }
    }

    private func navigateFile(forward: Bool) async -> Bool {
        await viewModel.selectAdjacentFile(forward: forward)
    }

    private func stageFiles(_ files: [FileStatus]) {
        guard let directory = viewModel.activeDirectory else {
            return
        }

        Task { @MainActor in
            do {
                try await viewModel.stage(files: files.filter { !$0.isStaged }, in: directory)
            } catch {
                onPresentGitError("Stage failed: \(error.localizedDescription)")
            }
        }
    }

    private func unstageFiles(_ files: [FileStatus]) {
        guard let directory = viewModel.activeDirectory else {
            return
        }

        Task { @MainActor in
            do {
                try await viewModel.unstage(files: files.filter(\.isStaged), in: directory)
            } catch {
                onPresentGitError("Unstage failed: \(error.localizedDescription)")
            }
        }
    }
}
