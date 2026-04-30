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
        if viewModel.isLoadingCommits {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)

                Text("Loading commits…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else if viewModel.commitsLoadState == .failed {
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
            DiffViewerCommitDiffFilesView(files: viewModel.commitDiffFiles)
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
        .appSelectableRow(isSelected: isSelected, identity: commit.id, action: onSelect)
        .accessibilityLabel("\(shortHash) \(commitTitle)")
    }

    private var shortHash: String {
        String(commit.hash.prefix(7))
    }

    private var commitTitle: String {
        commit.message.isEmpty ? "(no commit message)" : commit.message
    }
}

private struct DiffViewerCommitDiffFilesView: View {
    let files: [DiffFile]

    var body: some View {
        DiffPreviewScrollContainer {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                    DiffViewerCommitDiffFileSection(file: file)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .textSelection(.enabled)
        }
    }
}

private struct DiffViewerCommitDiffFileSection: View {
    let file: DiffFile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(verbatim: file.path)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if file.isBinary {
                    DiffPreviewBadge(title: "Binary", tone: .neutral)
                }

                if file.linesAdded > 0 {
                    DiffPreviewBadge(title: "+\(file.linesAdded)", tone: .added)
                }

                if file.linesDeleted > 0 {
                    DiffPreviewBadge(title: "-\(file.linesDeleted)", tone: .deleted)
                }
            }
            .accessibilityElement(children: .combine)

            diffContent
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var diffContent: some View {
        if file.isBinary {
            DiffCalloutCard(
                icon: "doc.fill",
                title: "Binary diff",
                message: "Binary file changes cannot be rendered inline yet."
            )
        } else if !file.hunks.isEmpty {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(Array(file.hunks.enumerated()), id: \.offset) { index, hunk in
                    DiffHunkSection(
                        hunk: hunk,
                        gutterLayout: DiffGutterLayout(hunk: hunk, defaultLineNumberWidth: lineNumberWidth),
                        fillsRemainingHeight: index == file.hunks.indices.last,
                        displayPolicy: .commitPreview
                    )
                }
            }
        } else {
            DiffCalloutCard(
                icon: "arrow.left.arrow.right",
                title: file.isRenamed ? "Rename only" : "No line changes",
                message: file.isRenamed
                    ? "This change renames the file without modifying any lines."
                    : "This change does not contain any line-based hunks to render."
            )
        }
    }

    private var lineNumberWidth: CGFloat {
        let maximumLineNumber = max(
            file.hunks.compactMap { $0.lines.compactMap(\.oldLineNumber).max() }.max() ?? 0,
            file.hunks.compactMap { $0.lines.compactMap(\.newLineNumber).max() }.max() ?? 0
        )
        let digits = max(String(maximumLineNumber).count, 2)
        return CGFloat((digits * 8) + 8)
    }
}
