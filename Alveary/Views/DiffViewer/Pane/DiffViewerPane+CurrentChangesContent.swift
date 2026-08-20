import SwiftUI

struct DiffViewerCurrentChangesContent: View, Equatable {
    let viewModel: DiffViewerViewModel
    /// Compared state arrives as plain values with change closures, never `@Binding`s.
    /// `==` has to be `nonisolated` to satisfy `Equatable`, while a binding's projected
    /// read is a main-actor computed property — comparing one there reads across
    /// isolation. `body` rebuilds the bindings its children need from these.
    /// The change closures are `@MainActor` because `Binding.init(get:set:)` wants a
    /// `@Sendable` setter, and a global-actor-isolated function value is one; these
    /// only ever run from `body` anyway.
    /// A rebuilt binding's getter is a per-pass snapshot, unlike a `@Binding` forwarded
    /// from the owner's storage: a child reading back what it just wrote inside one body
    /// pass sees the old value. `DiffViewerVerticalSplit`'s drag is safe because it
    /// captures its start fraction in `@State` rather than re-reading between frames.
    let topSectionFraction: CGFloat
    let onTopSectionFractionChange: @MainActor (CGFloat) -> Void
    let onTopSectionFractionCommit: (CGFloat) -> Void
    let isFileListTopDividerVisible: Bool
    let onFileListTopDividerVisibleChange: @MainActor (Bool) -> Void
    let fileDisplayName: (FileStatus) -> String
    let statusTitle: (FileStatus.Status) -> String
    let diffPreviewIdentity: (FileStatus) -> String
    let onPresentGitError: (String) -> Void
    let onDiscardFiles: ([FileStatus]) -> Void

    /// The pane re-runs its body on every resize-drag frame, and both modes stay mounted
    /// once visited, so without this each frame rebuilt two mode subtrees. Everything
    /// rendered here reads through `viewModel`, whose observation invalidates the body
    /// regardless of `==`; the closures are excluded because they capture only the pane's
    /// reference-typed dependencies and `@State` storage that outlives the struct copy.
    nonisolated static func == (lhs: DiffViewerCurrentChangesContent, rhs: DiffViewerCurrentChangesContent) -> Bool {
        lhs.viewModel === rhs.viewModel
            && lhs.topSectionFraction == rhs.topSectionFraction
            && lhs.isFileListTopDividerVisible == rhs.isFileListTopDividerVisible
    }

    @State private var latestKeyboardNavigationLoadID = UUID()

    /// Explicitly typed so the rebuilt bindings resolve in their own scope rather than
    /// on `body`'s type-check budget.
    ///
    /// Each setter is a closure literal that *calls* the change closure, never the change
    /// closure passed as a value. `Binding.init(set:)` takes an `@isolated(any)` function,
    /// so handing it a `@MainActor` one asks for a reabstraction thunk between the two
    /// isolation lowerings — and emitting that thunk crashes Swift 6.3.2's IRGen in Debug
    /// (`SyncCallEmission::setArgs`), which built green locally on a newer toolchain and
    /// failed only on CI. A literal is emitted at the abstraction level the parameter
    /// already wants, so no thunk exists to miscompile.
    private var topSectionFractionBinding: Binding<CGFloat> {
        Binding(get: { topSectionFraction }, set: { onTopSectionFractionChange($0) })
    }

    private var fileListTopDividerBinding: Binding<Bool> {
        Binding(get: { isFileListTopDividerVisible }, set: { onFileListTopDividerVisibleChange($0) })
    }

    var body: some View {
        DiffViewerVerticalSplit(
            splitFraction: topSectionFractionBinding,
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
                onSelectAllFiles: selectAllFiles,
                onNavigateFile: navigateFile,
                onStageFiles: stageFiles,
                onUnstageFiles: unstageFiles,
                onDiscardFiles: onDiscardFiles,
                isTopDividerVisible: fileListTopDividerBinding
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
                loadImage: { try await viewModel.loadImagePreview($0, intent: $1) },
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

    private func selectAllFiles() {
        latestKeyboardNavigationLoadID = UUID()
        guard let directory = viewModel.activeDirectory,
              let preparedSelection = viewModel.selectAllFilesImmediately(in: directory) else {
            return
        }

        Task {
            await viewModel.loadSelectedFileDiff(preparedSelection)
        }
    }

    private func navigateFile(
        forward: Bool,
        behavior: DiffViewerFileSelectionBehavior
    ) -> String? {
        guard let directory = viewModel.activeDirectory,
              let file = viewModel.adjacentFile(forward: forward),
              let preparedSelection = viewModel.selectFileImmediately(file, in: directory, behavior: behavior) else {
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
