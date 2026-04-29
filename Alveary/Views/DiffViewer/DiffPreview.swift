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
        .padding(.horizontal, 14)
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
        if diff.isBinary {
            DiffPreviewScrollContainer {
                VStack(alignment: .leading, spacing: 14) {
                    renameSummary
                    DiffCalloutCard(
                        icon: "doc.fill",
                        title: "Binary diff",
                        message: "Binary file changes cannot be rendered inline yet."
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else if !diff.hunks.isEmpty {
            DiffPreviewScrollContainer {
                LazyVStack(alignment: .leading, spacing: 14) {
                    renameSummary

                    ForEach(Array(diff.hunks.enumerated()), id: \.offset) { index, hunk in
                        DiffHunkSection(
                            hunk: hunk,
                            gutterLayout: DiffGutterLayout(hunk: hunk, defaultLineNumberWidth: lineNumberWidth),
                            fillsRemainingHeight: index == diff.hunks.indices.last
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .textSelection(.enabled)
            }
        } else if shouldUseStructuredEmptyState {
            DiffPreviewScrollContainer {
                VStack(alignment: .leading, spacing: 14) {
                    renameSummary
                    DiffCalloutCard(
                        icon: "arrow.left.arrow.right",
                        title: diff.isRenamed ? "Rename only" : "No line changes",
                        message: diff.isRenamed
                            ? "This change renames the file without modifying any lines."
                            : "This change does not contain any line-based hunks to render."
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            RawDiffFallbackView(
                rawDiffContent: rawDiffContent,
                note: "Showing the raw patch because this change does not expose line hunks yet."
            )
        }
    }

    private var lineNumberWidth: CGFloat {
        let maximumLineNumber = max(
            diff.hunks.compactMap { $0.lines.compactMap(\.oldLineNumber).max() }.max() ?? 0,
            diff.hunks.compactMap { $0.lines.compactMap(\.newLineNumber).max() }.max() ?? 0
        )
        let digits = max(String(maximumLineNumber).count, 2)
        return CGFloat((digits * 8) + 8)
    }

    @ViewBuilder
    private var renameSummary: some View {
        if diff.isRenamed,
           let oldPath = diff.oldPath,
           let newPath = diff.newPath {
            VStack(alignment: .leading, spacing: 8) {
                Label("Renamed file", systemImage: "arrow.left.arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: oldPath)
                    Image(systemName: "arrow.down")
                        .foregroundStyle(.secondary)
                    Text(verbatim: newPath)
                }
                .font(.system(.caption, design: .monospaced))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        }
    }

    private var shouldUseStructuredEmptyState: Bool {
        diff.isRenamed || rawDiffContent.isEmpty
    }
}

struct DiffHunkSection: View {
    let hunk: DiffHunk
    let gutterLayout: DiffGutterLayout
    let fillsRemainingHeight: Bool

    private let collapsedContextMinimum = 8
    private let visibleContextRadius = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: headerText)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05))

            ForEach(Array(displayRows.enumerated()), id: \.offset) { _, row in
                switch row {
                case .line(let line):
                    DiffLineRow(line: line, gutterLayout: gutterLayout)
                case .omitted(let summary):
                    DiffCollapsedContextRow(summary: summary, gutterLayout: gutterLayout)
                }
            }

            if fillsRemainingHeight {
                Spacer(minLength: 0)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(
            maxWidth: .infinity,
            maxHeight: fillsRemainingHeight ? .infinity : nil,
            alignment: .topLeading
        )
    }

    private var headerText: String {
        let oldRange = rangeText(prefix: "-", start: hunk.oldStart, count: hunk.oldCount)
        let newRange = rangeText(prefix: "+", start: hunk.newStart, count: hunk.newCount)
        return "@@ \(oldRange) \(newRange) @@\(headerSuffix)"
    }

    private var headerSuffix: String {
        guard let header = hunk.header,
              !header.isEmpty else {
            return ""
        }

        return " \(header)"
    }

    private func rangeText(prefix: String, start: Int, count: Int) -> String {
        if count == 1 {
            return "\(prefix)\(start)"
        }

        return "\(prefix)\(start),\(count)"
    }

    private var displayRows: [DiffHunkDisplayRow] {
        let changedIndices = hunk.lines.indices.filter { hunk.lines[$0].type != .context }
        guard !changedIndices.isEmpty else {
            return hunk.lines.map(DiffHunkDisplayRow.line)
        }

        var visibleIndices: Set<Int> = []
        for changedIndex in changedIndices {
            let lowerBound = max(0, changedIndex - visibleContextRadius)
            let upperBound = min(hunk.lines.count - 1, changedIndex + visibleContextRadius)
            for visibleIndex in lowerBound...upperBound {
                visibleIndices.insert(visibleIndex)
            }
        }

        var rows: [DiffHunkDisplayRow] = []
        var index = 0

        while index < hunk.lines.count {
            if visibleIndices.contains(index) {
                rows.append(.line(hunk.lines[index]))
                index += 1
                continue
            }

            let omittedStart = index
            while index < hunk.lines.count, !visibleIndices.contains(index) {
                index += 1
            }

            let omittedLines = Array(hunk.lines[omittedStart..<index])
            if omittedLines.count < collapsedContextMinimum {
                rows.append(contentsOf: omittedLines.map(DiffHunkDisplayRow.line))
                continue
            }

            rows.append(.omitted(summary: summary(for: omittedLines)))
        }

        return rows
    }

    private func summary(for omittedLines: [DiffLine]) -> CollapsedContextSummary {
        CollapsedContextSummary(
            lineCount: omittedLines.count,
            oldStart: omittedLines.first?.oldLineNumber,
            oldEnd: omittedLines.last?.oldLineNumber,
            newStart: omittedLines.first?.newLineNumber,
            newEnd: omittedLines.last?.newLineNumber
        )
    }
}

enum DiffHunkDisplayRow {
    case line(DiffLine)
    case omitted(summary: CollapsedContextSummary)
}
