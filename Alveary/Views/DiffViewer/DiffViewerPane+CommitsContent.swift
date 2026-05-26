import SwiftUI

struct DiffViewerCommitsContent: View {
    let viewModel: DiffViewerViewModel
    @Binding var topSectionFraction: CGFloat
    let onTopSectionFractionCommit: (CGFloat) -> Void

    @State private var scrollController = DiffViewerListScrollController()
    @State private var latestKeyboardNavigationScrollID = UUID()
    @State private var latestKeyboardNavigationLoadID = UUID()
    @State private var keyboardNavigationCommitID: String?
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
                        isSelected: commitSelectionID == commit.id
                    ) {
                        keyboardNavigationCommitID = commit.id
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
                .onKeyPress(keys: [.upArrow, .downArrow]) { keyPress in
                    handleCommitListKeyPress(keyPress, scrollProxy: scrollProxy)
                }
                .background {
                    DiffViewerFileListScrollMonitor(
                        fileIDs: viewModel.aheadCommits.map(\.id),
                        verticalOffsetFromTop: .constant(0),
                        scrollController: scrollController
                    )
                }
                .onChange(of: viewModel.selectedCommit?.id) { _, commitID in
                    keyboardNavigationCommitID = commitID
                }
                .onAppear {
                    keyboardNavigationCommitID = viewModel.selectedCommit?.id
                }
                .onDisappear {
                    latestKeyboardNavigationScrollID = UUID()
                    latestKeyboardNavigationLoadID = UUID()
                    keyboardNavigationCommitID = nil
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
                imagePreviews: viewModel.commitImagePreviews,
                showsFileHeaders: true,
                allowsFileCollapse: true,
                collapsedFileIDs: viewModel.selectedCommitCollapsedFileIDs,
                onToggleFileCollapse: { fileID in
                    viewModel.toggleSelectedCommitFileCollapse(fileID: fileID)
                },
                loadImage: viewModel.loadImagePreview,
                openImage: viewModel.openImagePreview
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

    private var commitSelectionID: String? {
        keyboardNavigationCommitID ?? viewModel.selectedCommit?.id
    }

    private func handleCommitListKeyPress(_ keyPress: KeyPress, scrollProxy: ScrollViewProxy) -> KeyPress.Result {
        switch keyPress.key {
        case .upArrow:
            navigateCommitList(forward: false, scrollProxy: scrollProxy)
            return .handled
        case .downArrow:
            navigateCommitList(forward: true, scrollProxy: scrollProxy)
            return .handled
        default:
            return .ignored
        }
    }

    private func navigateCommitList(forward: Bool, scrollProxy: ScrollViewProxy) {
        guard let commit = viewModel.adjacentCommit(from: commitSelectionID, forward: forward) else {
            return
        }
        keyboardNavigationCommitID = commit.id
        let loadID = UUID()
        latestKeyboardNavigationLoadID = loadID
        // Selection changes synchronously for row color; only the latest repeated key press should start preview work.
        Task { @MainActor in
            guard latestKeyboardNavigationLoadID == loadID else {
                return
            }
            await viewModel.selectCommit(commit)
        }
        scrollSelectionIntoView(scrollProxy: scrollProxy, id: commit.id)
    }

    private func claimCommitListKeyboardFocus() {
        latestKeyboardNavigationScrollID = UUID()
        latestKeyboardNavigationLoadID = UUID()
        chatComposerFocus?.release()
        isCommitListKeyboardFocused = true
    }

    private func scrollSelectionIntoView(scrollProxy: ScrollViewProxy, id: String) {
        let scrollID = UUID()
        latestKeyboardNavigationScrollID = scrollID
        if id == viewModel.aheadCommits.first?.id {
            scrollToListBoundary(scrollProxy: scrollProxy, rowID: id, edge: .top, scrollID: scrollID)
        } else if id == viewModel.aheadCommits.last?.id {
            scrollToListBoundary(scrollProxy: scrollProxy, rowID: id, edge: .bottom, scrollID: scrollID)
        } else {
            scrollToRow(scrollProxy: scrollProxy, rowID: id, scrollID: scrollID)
        }
    }

    private func scrollToListBoundary(
        scrollProxy: ScrollViewProxy,
        rowID: String,
        edge: DiffViewerListScrollEdge,
        scrollID: UUID
    ) {
        let didScroll = scrollController.scroll(to: edge, animated: true)
        if !didScroll {
            withAnimation(.easeInOut(duration: 0.18)) {
                scrollProxy.scrollTo(rowID, anchor: edge.fallbackAnchor)
            }
        }

        DispatchQueue.main.async {
            guard latestKeyboardNavigationScrollID == scrollID else {
                return
            }
            if !scrollController.scroll(to: edge, animated: true) {
                scrollProxy.scrollTo(rowID, anchor: edge.fallbackAnchor)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard latestKeyboardNavigationScrollID == scrollID else {
                return
            }
            _ = scrollController.scroll(to: edge, animated: false)
        }
    }

    private func scrollToRow(scrollProxy: ScrollViewProxy, rowID: String, scrollID: UUID) {
        withAnimation(.easeInOut(duration: 0.18)) {
            scrollProxy.scrollTo(rowID)
        }
        DispatchQueue.main.async {
            guard latestKeyboardNavigationScrollID == scrollID else {
                return
            }
            withAnimation(.easeInOut(duration: 0.18)) {
                scrollProxy.scrollTo(rowID)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            guard latestKeyboardNavigationScrollID == scrollID else {
                return
            }
            scrollProxy.scrollTo(rowID)
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
