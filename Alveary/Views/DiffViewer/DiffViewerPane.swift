import SwiftUI

enum DiffViewerPaneMetrics {
    // These compensate for macOS Menu/List/ScrollView chrome so rendered edges land on the 10pt pane inset.
    static let headerLeadingInset: CGFloat = 7
    static let headerTrailingInset: CGFloat = 11
    static let selectionBackgroundLeadingInset: CGFloat = 6
    static let selectionBackgroundTrailingInset: CGFloat = 11
    static let diffPreviewHorizontalInset: CGFloat = 6
    static let diffPreviewTopInset: CGFloat = 1
    static let diffPreviewBottomInset: CGFloat = 14
}

struct DiffViewerPane: View {
    let viewModel: DiffViewerViewModel
    let canCommit: Bool
    @Binding private var mode: DiffViewerMode
    let onModeCommit: (DiffViewerMode) -> Void
    @Binding private var topSectionFraction: CGFloat
    let onTopSectionFractionCommit: (CGFloat) -> Void
    let onCommitRequested: () -> Void

    @State private var pendingDiscardFiles: [FileStatus] = []
    @State private var isFileListTopDividerVisible = false

    init(
        viewModel: DiffViewerViewModel,
        canCommit: Bool,
        mode: Binding<DiffViewerMode> = .constant(.currentChanges),
        onModeCommit: @escaping (DiffViewerMode) -> Void = { _ in },
        topSectionFraction: Binding<CGFloat> = .constant(CGFloat(AppSettings.defaultDiffViewerTopSectionFraction)),
        onTopSectionFractionCommit: @escaping (CGFloat) -> Void = { _ in },
        onCommitRequested: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.canCommit = canCommit
        _mode = mode
        self.onModeCommit = onModeCommit
        _topSectionFraction = topSectionFraction
        self.onTopSectionFractionCommit = onTopSectionFractionCommit
        self.onCommitRequested = onCommitRequested
    }

    var body: some View {
        VStack(spacing: 0) {
            DiffViewerPaneHeader(
                activeDirectory: viewModel.activeDirectory,
                mode: mode,
                contextualAction: viewModel.contextualAction,
                selectedFiles: viewModel.selectedFiles,
                canCommit: canCommit,
                showsFileListDivider: isFileListTopDividerVisible,
                showsFileActions: mode == .currentChanges,
                onModeSelected: selectMode,
                onCommitRequested: onCommitRequested,
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
                content
            }
        }
        .onAppear(perform: syncCommitModeActivity)
        .onDisappear {
            viewModel.setCommitModeActive(false)
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .commits {
                isFileListTopDividerVisible = false
                loadCommitsIfNeeded()
            } else {
                viewModel.setCommitModeActive(false)
            }
        }
        .onChange(of: viewModel.activeDirectory) { _, _ in
            if mode == .commits {
                loadCommitsIfNeeded()
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
    @ViewBuilder
    var content: some View {
        switch mode {
        case .currentChanges:
            DiffViewerCurrentChangesContent(
                viewModel: viewModel,
                topSectionFraction: $topSectionFraction,
                onTopSectionFractionCommit: onTopSectionFractionCommit,
                isFileListTopDividerVisible: $isFileListTopDividerVisible,
                fileDisplayName: fileDisplayName,
                statusTitle: statusTitle,
                diffPreviewIdentity: diffPreviewIdentity,
                onPresentGitError: viewModel.presentGitError,
                onDiscardFiles: { pendingDiscardFiles = $0 }
            )
        case .commits:
            DiffViewerCommitsContent(
                viewModel: viewModel,
                topSectionFraction: $topSectionFraction,
                onTopSectionFractionCommit: onTopSectionFractionCommit
            )
        }
    }

    func selectMode(_ selectedMode: DiffViewerMode) {
        mode = selectedMode
        onModeCommit(selectedMode)
    }

    func syncCommitModeActivity() {
        if mode == .commits {
            loadCommitsIfNeeded()
        } else {
            viewModel.setCommitModeActive(false)
        }
    }

    func loadCommitsIfNeeded() {
        guard mode == .commits else {
            return
        }

        Task {
            await viewModel.loadAheadCommitsForActiveTarget()
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
