import SwiftUI

struct DiffViewerCommitsContent: View {
    let viewModel: DiffViewerViewModel
    @Binding var topSectionFraction: CGFloat
    let onTopSectionFractionCommit: (CGFloat) -> Void

    @State private var pendingKeyboardNavigationScrollCount = 0
    @FocusState private var isCommitListKeyboardFocused: Bool
    @FocusedValue(\.chatComposerFocus) private var chatComposerFocus

    var body: some View {
        DiffViewerVerticalSplit(
            splitFraction: $topSectionFraction,
            bounds: AppSettings.supportedDiffViewerSplitRange,
            onCommit: onTopSectionFractionCommit
        ) {
            commitList
        } bottom: {
            commitDiffPreview
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var commitList: some View {
        if viewModel.isLoadingCommits && viewModel.aheadCommits.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)

                Text("Loading commits…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else if viewModel.commitsLoadState == .failed && viewModel.aheadCommits.isEmpty {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                heading: "Unable to load commits",
                subtext: "Reopen the diff viewer to try again.",
                actions: []
            )
        } else if viewModel.aheadCommits.isEmpty {
            EmptyStateView(
                icon: "checkmark.circle",
                heading: "No local commits",
                subtext: "There are no commits ahead of base.",
                actions: []
            )
        } else {
            ScrollViewReader { scrollProxy in
                List(viewModel.aheadCommits) { commit in
                    DiffViewerCommitRow(
                        commit: commit,
                        isSelected: viewModel.selectedCommit?.id == commit.id
                    ) {
                        claimCommitListKeyboardFocus()
                        Task {
                            await viewModel.selectCommit(commit)
                        }
                    }
                }
                .selectionDisabled()
                .contentMargins(.top, 0, for: .scrollContent)
                .contentMargins(.horizontal, 0, for: .scrollContent)
                .contentMargins(.bottom, 4, for: .scrollContent)
                .clipped()
                .focusable()
                .focused($isCommitListKeyboardFocused)
                .focusEffectDisabled()
                .onKeyPress(keys: [.upArrow, .downArrow], action: handleCommitListKeyPress)
                .onChange(of: viewModel.selectedCommit?.id) { _, commitID in
                    guard let commitID,
                          pendingKeyboardNavigationScrollCount > 0 else {
                        return
                    }
                    pendingKeyboardNavigationScrollCount -= 1
                    scrollSelectionIntoView(scrollProxy: scrollProxy, id: commitID)
                }
                .onDisappear {
                    pendingKeyboardNavigationScrollCount = 0
                }
            }
        }
    }

    @ViewBuilder
    private var commitDiffPreview: some View {
        if viewModel.isLoadingSelectedCommitDiff {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)

                Text("Loading commit diff…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else if viewModel.selectedCommitDiffLoadState == .failed {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                heading: commitDiffFailureHeading,
                subtext: commitDiffFailureSubtext,
                actions: []
            )
        } else if viewModel.selectedCommit == nil {
            EmptyStateView(
                icon: "point.topleft.down.curvedto.point.bottomright.up",
                heading: "Select a commit",
                subtext: "Choose a local commit to inspect its file diffs.",
                actions: []
            )
        } else if !viewModel.commitDiffFiles.isEmpty {
            FlattenedDiffPreview(
                files: viewModel.commitDiffFiles,
                showsFileHeaders: true,
                allowsFileCollapse: true,
                collapsedFileIDs: viewModel.selectedCommitCollapsedFileIDs,
                onToggleFileCollapse: { fileID in
                    viewModel.toggleSelectedCommitFileCollapse(fileID: fileID)
                }
            )
        } else if !viewModel.rawCommitDiffContent.isEmpty {
            RawDiffFallbackView(
                rawDiffContent: viewModel.rawCommitDiffContent,
                note: "Showing the raw patch because the commit diff could not be parsed into files."
            )
        } else {
            EmptyStateView(
                icon: "doc.plaintext",
                heading: "No commit diff",
                subtext: "This commit does not contain a previewable patch.",
                actions: []
            )
        }
    }

    private var commitDiffFailureHeading: String {
        guard let message = viewModel.selectedCommitDiffErrorMessage,
              message.localizedCaseInsensitiveContains("too large")
                || message.localizedCaseInsensitiveContains("exceeded") else {
            return "Unable to load commit diff"
        }

        return "Commit diff is too large"
    }

    private var commitDiffFailureSubtext: String {
        viewModel.selectedCommitDiffErrorMessage ?? "Select the commit again to try again."
    }

    private func handleCommitListKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        switch keyPress.key {
        case .upArrow:
            navigateCommitList(forward: false)
            return .handled
        case .downArrow:
            navigateCommitList(forward: true)
            return .handled
        default:
            return .ignored
        }
    }

    private func navigateCommitList(forward: Bool) {
        pendingKeyboardNavigationScrollCount += 1
        Task { @MainActor in
            let didMove = await viewModel.selectAdjacentCommit(forward: forward)
            if !didMove, pendingKeyboardNavigationScrollCount > 0 {
                pendingKeyboardNavigationScrollCount -= 1
            }
        }
    }

    private func claimCommitListKeyboardFocus() {
        pendingKeyboardNavigationScrollCount = 0
        chatComposerFocus?.wrappedValue = false
        isCommitListKeyboardFocused = true
    }

    private func scrollSelectionIntoView(scrollProxy: ScrollViewProxy, id: String) {
        withAnimation(.easeInOut(duration: 0.18)) {
            scrollProxy.scrollTo(id)
        }
    }
}

private struct DiffViewerCommitRow: View {
    let commit: CommitInfo
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(shortHash)
                .fontWeight(.bold)

            Text(commitTitle)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .appSelectableRow(
            isSelected: isSelected,
            identity: commit.id,
            selectionBackgroundLeadingInset: DiffViewerPaneMetrics.selectionBackgroundLeadingInset,
            selectionBackgroundTrailingInset: DiffViewerPaneMetrics.selectionBackgroundTrailingInset,
            action: onSelect
        )
        .accessibilityLabel("\(shortHash) \(commitTitle)")
    }

    private var shortHash: String {
        String(commit.hash.prefix(7))
    }

    private var commitTitle: String {
        commit.message.isEmpty ? "(no commit message)" : commit.message
    }
}
