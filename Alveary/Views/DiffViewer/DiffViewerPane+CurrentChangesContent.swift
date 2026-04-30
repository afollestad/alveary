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
    @State private var latestKeyboardNavigationLoadID = UUID()

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
                imagePreview: viewModel.imagePreview,
                rawDiffContent: viewModel.rawDiffContent,
                errorMessage: viewModel.selectedDiffErrorMessage,
                isPending: viewModel.isSelectedDiffPending,
                isLoading: viewModel.isLoadingSelectedDiff,
                fileDisplayName: fileDisplayName,
                statusTitle: statusTitle,
                diffPreviewIdentity: diffPreviewIdentity,
                loadImage: viewModel.loadImagePreview,
                openImage: viewModel.openImagePreview
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectFile(_ file: FileStatus, behavior: DiffViewerFileSelectionBehavior) {
        latestKeyboardNavigationLoadID = UUID()
        guard let directory = viewModel.activeDirectory,
              let preparedSelection = viewModel.selectFileImmediately(file, in: directory, behavior: behavior) else {
            return
        }

        Task {
            await viewModel.loadSelectedFileDiff(preparedSelection)
        }
    }

    private func navigateFile(forward: Bool) -> String? {
        guard let directory = viewModel.activeDirectory,
              let file = viewModel.adjacentFile(forward: forward),
              let preparedSelection = viewModel.selectFileImmediately(file, in: directory, behavior: .single) else {
            return nil
        }

        let loadID = UUID()
        latestKeyboardNavigationLoadID = loadID
        // Selection changes synchronously for row color; only the latest repeated key press should start preview work.
        Task { @MainActor in
            guard latestKeyboardNavigationLoadID == loadID else {
                return
            }
            await viewModel.loadSelectedFileDiff(preparedSelection)
        }
        return file.id
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
