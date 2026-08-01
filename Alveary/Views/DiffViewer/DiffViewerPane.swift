import SwiftUI

enum DiffViewerPaneMetrics {
    // Every rendered horizontal edge lands on `ContextualPaneLayout.horizontalInset`,
    // so this pane matches the contextual panes it shares the right-pane lane with.
    // The raw numbers differ because macOS List/ScrollView chrome insets content by
    // different amounts; the header hosts no such chrome now that mode is a chip row,
    // so it takes the inset directly. Derive them from the shared constant rather
    // than hardcoding, so the two panes cannot drift apart again.
    static let headerLeadingInset = ContextualPaneLayout.horizontalInset
    /// Exactly the shared inset, with no compensation: the header's trailing
    /// element is the same `ModalCloseButton` the contextual panes put at that
    /// inset, so any offset here reads as the two panes' close buttons not
    /// lining up as they swap in the shared lane.
    static let headerTrailingInset = ContextualPaneLayout.horizontalInset
    static let selectionBackgroundLeadingInset = ContextualPaneLayout.horizontalInset - 4
    static let selectionBackgroundTrailingInset = ContextualPaneLayout.horizontalInset + 1
    static let diffPreviewHorizontalInset = ContextualPaneLayout.horizontalInset - 4
    /// The preview's inset *inside* its scroll container — not a pane edge. The
    /// pull-request pane adds this to its own pane inset to fold both into one
    /// scroll padding, so it must stay independent of the diff viewer's edge.
    static let diffPreviewContentInset: CGFloat = 6
    static let diffPreviewTopInset: CGFloat = 1
    static let diffPreviewBottomInset: CGFloat = 14
    /// Width the header reserves for its trailing close button, so the button
    /// keeps its own lane instead of competing with the clipping action row.
    static let headerCloseButtonReservedWidth = ActionButtonMetrics.iconButtonDiameter + 6
}

struct DiffViewerPane: View {
    let viewModel: DiffViewerViewModel
    let canCommit: Bool
    let canCreatePullRequest: Bool
    let canViewPullRequest: Bool
    @Binding private var mode: DiffViewerMode
    let onModeCommit: (DiffViewerMode) -> Void
    @Binding private var topSectionFraction: CGFloat
    let onTopSectionFractionCommit: (CGFloat) -> Void
    let onCommitRequested: () -> Void
    let onCreatePullRequestRequested: () -> Void
    let onViewPullRequestRequested: () -> Void
    let onClose: () -> Void

    @State private var pendingDiscardFiles: [FileStatus] = []
    @State private var isFileListTopDividerVisible = false
    @State private var isPushInFlight = false
    @State private var isForcePushConfirmationPresented = false

    init(
        viewModel: DiffViewerViewModel,
        canCommit: Bool,
        canCreatePullRequest: Bool = false,
        canViewPullRequest: Bool = false,
        mode: Binding<DiffViewerMode> = .constant(.currentChanges),
        onModeCommit: @escaping (DiffViewerMode) -> Void = { _ in },
        topSectionFraction: Binding<CGFloat> = .constant(CGFloat(AppSettings.defaultDiffViewerTopSectionFraction)),
        onTopSectionFractionCommit: @escaping (CGFloat) -> Void = { _ in },
        onCommitRequested: @escaping () -> Void,
        onCreatePullRequestRequested: @escaping () -> Void = {},
        onViewPullRequestRequested: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.canCommit = canCommit
        self.canCreatePullRequest = canCreatePullRequest
        self.canViewPullRequest = canViewPullRequest
        _mode = mode
        self.onModeCommit = onModeCommit
        _topSectionFraction = topSectionFraction
        self.onTopSectionFractionCommit = onTopSectionFractionCommit
        self.onCommitRequested = onCommitRequested
        self.onCreatePullRequestRequested = onCreatePullRequestRequested
        self.onViewPullRequestRequested = onViewPullRequestRequested
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            DiffViewerPaneHeader(
                activeDirectory: viewModel.activeDirectory,
                mode: mode,
                selectedFiles: viewModel.selectedFiles,
                showsFileListDivider: isFileListTopDividerVisible,
                showsFileActions: mode == .currentChanges,
                onModeSelected: selectMode,
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
                },
                onClose: onClose
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

                DiffViewerPaneFooter(
                    actions: footerActions,
                    isPerformingAction: isPushInFlight,
                    onAction: performFooterAction
                )
            }
        }
        .modifier(DiffViewerForcePushDialog(
            isPresented: $isForcePushConfirmationPresented,
            onForcePush: { performPush(force: true) }
        ))
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

    var footerActions: [DiffViewerFooterAction] {
        DiffViewerFooterAction.available(
            workingState: viewModel.workingState,
            canCommit: canCommit,
            canCreatePullRequest: canCreatePullRequest,
            canViewPullRequest: canViewPullRequest
        )
    }

    func performFooterAction(_ kind: DiffViewerFooterAction.Kind) {
        switch kind {
        case .commit:
            onCommitRequested()
        case .push:
            performPush(force: false)
        case .createPullRequest:
            onCreatePullRequestRequested()
        case .viewPullRequest:
            onViewPullRequestRequested()
        }
    }

    func performPush(force: Bool) {
        guard let directory = viewModel.activeDirectory, !isPushInFlight else {
            return
        }
        isPushInFlight = true
        Task {
            defer { isPushInFlight = false }
            do {
                try await viewModel.push(force: force, in: directory)
            } catch GitError.nonFastForwardPushRequired(_) {
                isForcePushConfirmationPresented = true
            } catch {
                viewModel.presentGitError("Push failed: \(error.localizedDescription)")
            }
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

/// Lifted out of `body` (type-check budget); armed when an ordinary push is
/// rejected as non-fast-forward, mirroring the commit modal's force-push offer.
private struct DiffViewerForcePushDialog: ViewModifier {
    @Binding var isPresented: Bool
    let onForcePush: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Force push?",
            isPresented: $isPresented
        ) {
            Button("Force push", role: .destructive, action: onForcePush)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The remote branch has commits this branch does not. Force pushing will overwrite them.")
        }
    }
}
