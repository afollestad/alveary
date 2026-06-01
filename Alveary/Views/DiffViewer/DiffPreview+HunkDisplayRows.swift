import SwiftUI

enum DiffPreviewHunkDisplayRows {
    private static let collapsedContextMinimum = 8
    private static let visibleContextRadius = 3

    static func makeRows(for hunk: DiffHunk) -> [DiffHunkDisplayRow] {
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

            let omittedLines = hunk.lines[omittedStart..<index]
            if omittedLines.count < collapsedContextMinimum {
                rows.append(contentsOf: omittedLines.map(DiffHunkDisplayRow.line))
                continue
            }

            rows.append(.omitted(summary: summary(for: omittedLines)))
        }

        return rows
    }

    private static func summary(for omittedLines: ArraySlice<DiffLine>) -> CollapsedContextSummary {
        CollapsedContextSummary(
            lineCount: omittedLines.count,
            oldStart: omittedLines.first?.oldLineNumber,
            oldEnd: omittedLines.last?.oldLineNumber,
            newStart: omittedLines.first?.newLineNumber,
            newEnd: omittedLines.last?.newLineNumber,
            addedCount: omittedLines.filter { $0.type == .added }.count,
            deletedCount: omittedLines.filter { $0.type == .deleted }.count
        )
    }
}

enum DiffHunkDisplayRow: Sendable {
    case line(DiffLine)
    case omitted(summary: CollapsedContextSummary)
}

struct DiffPreviewHunkHeader: View {
    let hunk: DiffHunk

    var body: some View {
        Text(verbatim: headerText)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .diffPreviewIntrinsicMinimumContentWidthFrame()
            .background(Color.primary.opacity(0.05))
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(
                UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 12, bottomLeading: 0, bottomTrailing: 0, topTrailing: 12),
                    style: .continuous
                )
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
}
