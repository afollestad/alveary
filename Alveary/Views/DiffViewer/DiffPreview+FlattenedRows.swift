import AppKit
import SwiftUI

struct FlattenedDiffPreview: View {
    private static let synchronousLineThreshold = 1_000

    let files: [DiffFile]
    let showsFileHeaders: Bool
    @State private var preparedRows: [FlattenedDiffPreviewRow] = []
    @State private var preparedRowsID: Int?

    init(files: [DiffFile], showsFileHeaders: Bool) {
        self.files = files
        self.showsFileHeaders = showsFileHeaders
    }

    var body: some View {
        let currentRenderID = renderFingerprint
        if estimatedLineCount <= Self.synchronousLineThreshold {
            rowsView(FlattenedDiffPreviewRows.makeRows(files: files, showsFileHeaders: showsFileHeaders))
                .task(id: currentRenderID) {
                    clearPreparedRows()
                }
        } else if preparedRowsID == currentRenderID {
            rowsView(preparedRows)
        } else {
            preparingView
                .task(id: currentRenderID) {
                    let files = files
                    let showsFileHeaders = showsFileHeaders
                    let currentRenderID = currentRenderID
                    preparedRows = []
                    preparedRowsID = nil
                    let rowTask = Task.detached(priority: .userInitiated) {
                        try FlattenedDiffPreviewRows.makeRowsUnlessCancelled(files: files, showsFileHeaders: showsFileHeaders)
                    }
                    do {
                        // Propagate SwiftUI task cancellation into the detached row builder.
                        let rows = try await withTaskCancellationHandler {
                            try await rowTask.value
                        } onCancel: {
                            rowTask.cancel()
                        }
                        guard !Task.isCancelled else {
                            return
                        }
                        preparedRows = rows
                        preparedRowsID = currentRenderID
                    } catch is CancellationError {
                        rowTask.cancel()
                        return
                    } catch {
                        rowTask.cancel()
                    }
                }
        }
    }

    private func clearPreparedRows() {
        preparedRows = []
        preparedRowsID = nil
    }

    private func rowsView(_ rows: [FlattenedDiffPreviewRow]) -> some View {
        DiffPreviewScrollContainer {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    FlattenedDiffPreviewRenderRow(row: row)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .textSelection(.enabled)
        }
    }

    private var preparingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text("Preparing diff preview...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var estimatedLineCount: Int {
        files.reduce(0) { total, file in
            total + file.hunks.reduce(0) { $0 + $1.lines.count }
        }
    }

    private var renderFingerprint: Int {
        // Include line content so a large diff cannot reuse prepared rows from
        // another diff with the same file paths and hunk shape.
        var hasher = Hasher()
        hasher.combine(showsFileHeaders)
        for file in files {
            hasher.combine(file.oldPath)
            hasher.combine(file.newPath)
            hasher.combine(file.isBinary)
            hasher.combine(file.isRenamed)
            for hunk in file.hunks {
                hasher.combine(hunk.oldStart)
                hasher.combine(hunk.oldCount)
                hasher.combine(hunk.newStart)
                hasher.combine(hunk.newCount)
                hasher.combine(hunk.header)
                for line in hunk.lines {
                    hasher.combine(line.type.hashKey)
                    hasher.combine(line.oldLineNumber)
                    hasher.combine(line.newLineNumber)
                    hasher.combine(line.content)
                }
            }
        }
        return hasher.finalize()
    }
}

private extension DiffLine.LineType {
    var hashKey: Int {
        switch self {
        case .context:
            return 0
        case .added:
            return 1
        case .deleted:
            return 2
        }
    }
}

private enum FlattenedDiffPreviewRows {
    static func makeRows(files: [DiffFile], showsFileHeaders: Bool) -> [FlattenedDiffPreviewRow] {
        (try? makeRows(files: files, showsFileHeaders: showsFileHeaders, checksCancellation: false)) ?? []
    }

    static func makeRowsUnlessCancelled(files: [DiffFile], showsFileHeaders: Bool) throws -> [FlattenedDiffPreviewRow] {
        try makeRows(files: files, showsFileHeaders: showsFileHeaders, checksCancellation: true)
    }

    private static func makeRows(
        files: [DiffFile],
        showsFileHeaders: Bool,
        checksCancellation: Bool
    ) throws -> [FlattenedDiffPreviewRow] {
        // Keep diff rows flat so LazyVStack can virtualize individual line rows instead of whole hunks.
        var allRows: [FlattenedDiffPreviewRow] = []
        for (fileIndex, file) in files.enumerated() {
            try checkCancellationIfNeeded(checksCancellation)
            var rows: [FlattenedDiffPreviewRow] = []
            if showsFileHeaders {
                rows.append(.fileHeader(id: "file-\(fileIndex)-header", file: file, topPadding: fileIndex == 0 ? 0 : 18))
            }

            if file.isRenamed,
               let oldPath = file.oldPath,
               let newPath = file.newPath {
                rows.append(.renameSummary(id: "file-\(fileIndex)-rename", oldPath: oldPath, newPath: newPath))
            }

            if file.isBinary {
                rows.append(.binaryCallout(id: "file-\(fileIndex)-binary"))
            } else if file.hunks.isEmpty {
                rows.append(.emptyCallout(id: "file-\(fileIndex)-empty", isRenamed: file.isRenamed))
            } else {
                rows.append(contentsOf: try hunkRows(for: file, fileIndex: fileIndex, checksCancellation: checksCancellation))
            }

            allRows.append(contentsOf: rows)
        }

        return allRows
    }

    private static func hunkRows(
        for file: DiffFile,
        fileIndex: Int,
        checksCancellation: Bool
    ) throws -> [FlattenedDiffPreviewRow] {
        let lineNumberWidth = lineNumberWidth(for: file)
        var allRows: [FlattenedDiffPreviewRow] = []
        for (hunkIndex, hunk) in file.hunks.enumerated() {
            try checkCancellationIfNeeded(checksCancellation)
            let gutterLayout = DiffGutterLayout(hunk: hunk, defaultLineNumberWidth: lineNumberWidth)
            var rows: [FlattenedDiffPreviewRow] = [
                .hunkHeader(
                    id: "file-\(fileIndex)-hunk-\(hunkIndex)-header",
                    hunk: hunk,
                    topPadding: hunkIndex == 0 ? 0 : 14
                )
            ]

            let displayRows = DiffPreviewHunkDisplayRows.makeRows(for: hunk)
            for (rowIndex, displayRow) in displayRows.enumerated() {
                try checkCancellationIfNeeded(checksCancellation)
                let isLastInHunk = rowIndex == displayRows.indices.last
                let bottomPadding: CGFloat = isLastInHunk && hunkIndex != file.hunks.indices.last ? 14 : 0
                switch displayRow {
                case .line(let line):
                    rows.append(
                        .line(
                            id: "file-\(fileIndex)-hunk-\(hunkIndex)-line-\(rowIndex)",
                            line: line,
                            gutterLayout: gutterLayout,
                            isLastInHunk: isLastInHunk,
                            bottomPadding: bottomPadding
                        )
                    )
                case .omitted(let summary):
                    rows.append(
                        .collapsed(
                            id: "file-\(fileIndex)-hunk-\(hunkIndex)-collapsed-\(rowIndex)",
                            summary: summary,
                            gutterLayout: gutterLayout,
                            isLastInHunk: isLastInHunk,
                            bottomPadding: bottomPadding
                        )
                    )
                }
            }

            allRows.append(contentsOf: rows)
        }

        return allRows
    }

    private static func lineNumberWidth(for file: DiffFile) -> CGFloat {
        let maximumLineNumber = max(
            file.hunks.compactMap { $0.lines.compactMap(\.oldLineNumber).max() }.max() ?? 0,
            file.hunks.compactMap { $0.lines.compactMap(\.newLineNumber).max() }.max() ?? 0
        )
        let digits = max(String(maximumLineNumber).count, 2)
        return CGFloat((digits * 8) + 8)
    }

    private static func checkCancellationIfNeeded(_ checksCancellation: Bool) throws {
        if checksCancellation {
            try Task.checkCancellation()
        }
    }
}

private enum FlattenedDiffPreviewRow: Identifiable, Sendable {
    case fileHeader(id: String, file: DiffFile, topPadding: CGFloat)
    case renameSummary(id: String, oldPath: String, newPath: String)
    case binaryCallout(id: String)
    case emptyCallout(id: String, isRenamed: Bool)
    case hunkHeader(id: String, hunk: DiffHunk, topPadding: CGFloat)
    case line(id: String, line: DiffLine, gutterLayout: DiffGutterLayout, isLastInHunk: Bool, bottomPadding: CGFloat)
    case collapsed(id: String, summary: CollapsedContextSummary, gutterLayout: DiffGutterLayout, isLastInHunk: Bool, bottomPadding: CGFloat)

    var id: String {
        switch self {
        case .fileHeader(let id, _, _),
             .renameSummary(let id, _, _),
             .binaryCallout(let id),
             .emptyCallout(let id, _),
             .hunkHeader(let id, _, _),
             .line(let id, _, _, _, _),
             .collapsed(let id, _, _, _, _):
            return id
        }
    }
}

private struct FlattenedDiffPreviewRenderRow: View {
    let row: FlattenedDiffPreviewRow

    var body: some View {
        switch row {
        case .fileHeader(_, let file, let topPadding):
            DiffPreviewFileHeader(file: file)
                .padding(.top, topPadding)
                .padding(.bottom, 10)
        case .renameSummary(_, let oldPath, let newPath):
            DiffPreviewRenameSummary(oldPath: oldPath, newPath: newPath)
                .padding(.bottom, 14)
        case .binaryCallout:
            DiffCalloutCard(
                icon: "doc.fill",
                title: "Binary diff",
                message: "Binary file changes cannot be rendered inline yet."
            )
        case .emptyCallout(_, let isRenamed):
            DiffCalloutCard(
                icon: "arrow.left.arrow.right",
                title: isRenamed ? "Rename only" : "No line changes",
                message: isRenamed
                    ? "This change renames the file without modifying any lines."
                    : "This change does not contain any line-based hunks to render."
            )
        case .hunkHeader(_, let hunk, let topPadding):
            DiffPreviewHunkHeader(hunk: hunk)
                .padding(.top, topPadding)
        case .line(_, let line, let gutterLayout, let isLastInHunk, let bottomPadding):
            DiffLineRow(line: line, gutterLayout: gutterLayout)
                .diffPreviewFlattenedHunkRow(isLastInHunk: isLastInHunk, bottomPadding: bottomPadding)
        case .collapsed(_, let summary, let gutterLayout, let isLastInHunk, let bottomPadding):
            DiffCollapsedContextRow(summary: summary, gutterLayout: gutterLayout)
                .diffPreviewFlattenedHunkRow(isLastInHunk: isLastInHunk, bottomPadding: bottomPadding)
        }
    }
}

private struct DiffPreviewFileHeader: View {
    let file: DiffFile

    var body: some View {
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
    }
}

private struct DiffPreviewRenameSummary: View {
    let oldPath: String
    let newPath: String

    var body: some View {
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

private struct DiffPreviewHunkHeader: View {
    let hunk: DiffHunk

    var body: some View {
        Text(verbatim: headerText)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
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

private enum DiffPreviewHunkDisplayRows {
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

private extension View {
    func diffPreviewFlattenedHunkRow(isLastInHunk: Bool, bottomPadding: CGFloat) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 0,
                        bottomLeading: isLastInHunk ? 12 : 0,
                        bottomTrailing: isLastInHunk ? 12 : 0,
                        topTrailing: 0
                    ),
                    style: .continuous
                )
            )
            .padding(.bottom, bottomPadding)
    }
}

enum DiffHunkDisplayRow: Sendable {
    case line(DiffLine)
    case omitted(summary: CollapsedContextSummary)
}
