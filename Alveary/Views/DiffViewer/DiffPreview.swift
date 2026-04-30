import AppKit
import SwiftUI

struct DiffPreviewHeader: View {
    let title: String
    let fileStatus: FileStatus
    let parsedDiff: DiffFile?
    let statusTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            HStack(spacing: 6) {
                DiffPreviewBadge(title: fileStatus.isStaged ? "Staged" : "Unstaged", tone: .neutral)
                DiffPreviewBadge(title: statusTitle, tone: badgeTone(for: fileStatus.status))

                if let parsedDiff {
                    if parsedDiff.isBinary {
                        DiffPreviewBadge(title: "Binary", tone: .neutral)
                    }

                    if parsedDiff.linesAdded > 0 {
                        DiffPreviewBadge(title: "+\(parsedDiff.linesAdded)", tone: .added)
                    }

                    if parsedDiff.linesDeleted > 0 {
                        DiffPreviewBadge(title: "-\(parsedDiff.linesDeleted)", tone: .deleted)
                    }
                }
            }
            .accessibilityElement(children: .contain)
        }
        .padding(.horizontal, DiffViewerPaneMetrics.diffPreviewHorizontalInset)
        .padding(.top, 14)
    }

    private func badgeTone(for status: FileStatus.Status) -> DiffPreviewBadge.Tone {
        switch status {
        case .added, .untracked:
            return .added
        case .deleted:
            return .deleted
        case .renamed, .copied:
            return .accent
        case .modified, .unmerged:
            return .neutral
        }
    }
}

struct DiffPreviewContent: View {
    let parsedDiff: DiffFile?
    let rawDiffContent: String
    let isPending: Bool
    let isLoading: Bool

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)

                    Text("Loading diff preview…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else if isPending {
                // During the spinner grace period, avoid flashing an empty-state
                // message for a diff that is still actively loading.
                Color.clear
            } else if let parsedDiff {
                StructuredDiffPreview(diff: parsedDiff, rawDiffContent: rawDiffContent)
            } else if rawDiffContent.isEmpty {
                EmptyStateView(
                    icon: "doc.plaintext",
                    heading: "No diff preview available",
                    subtext: "This file does not currently have a previewable diff.",
                    actions: []
                )
            } else {
                RawDiffFallbackView(
                    rawDiffContent: rawDiffContent,
                    note: "Showing the raw patch because the diff could not be parsed into hunks."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isLoading ? .center : .topLeading)
    }
}

struct StructuredDiffPreview: View {
    let diff: DiffFile
    let rawDiffContent: String

    var body: some View {
        if shouldUseRawFallback {
            RawDiffFallbackView(
                rawDiffContent: rawDiffContent,
                note: "Showing the raw patch because this change does not expose line hunks yet."
            )
        } else {
            FlattenedDiffPreview(files: [diff], showsFileHeaders: false)
        }
    }

    private var shouldUseRawFallback: Bool {
        !diff.isBinary && diff.hunks.isEmpty && !diff.isRenamed && !rawDiffContent.isEmpty
    }
}
