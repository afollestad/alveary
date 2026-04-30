import SwiftUI

struct DiffViewerCommitsContent: View {
    let viewModel: DiffViewerViewModel
    @Binding var topSectionFraction: CGFloat
    let onTopSectionFractionCommit: (CGFloat) -> Void

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
            List(viewModel.aheadCommits) { commit in
                DiffViewerCommitRow(
                    commit: commit,
                    isSelected: viewModel.selectedCommit?.id == commit.id
                ) {
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
            FlattenedDiffPreview(files: viewModel.commitDiffFiles, showsFileHeaders: true)
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
