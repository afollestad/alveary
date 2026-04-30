import AppKit
import SwiftUI

struct FlattenedDiffPreview: View {
    private static let synchronousLineThreshold = 1_000

    let files: [DiffFile]
    let showsFileHeaders: Bool
    let allowsFileCollapse: Bool
    let collapsedFileIDs: Set<String>
    let onToggleFileCollapse: (String) -> Void
    @State private var preparedRows: [FlattenedDiffPreviewRow] = []
    @State private var preparedRowsID: Int?

    init(
        files: [DiffFile],
        showsFileHeaders: Bool,
        allowsFileCollapse: Bool = false,
        collapsedFileIDs: Set<String> = [],
        onToggleFileCollapse: @escaping (String) -> Void = { _ in }
    ) {
        self.files = files
        self.showsFileHeaders = showsFileHeaders
        self.allowsFileCollapse = allowsFileCollapse
        self.collapsedFileIDs = collapsedFileIDs
        self.onToggleFileCollapse = onToggleFileCollapse
    }

    var body: some View {
        let currentRenderID = renderFingerprint
        if estimatedLineCount <= Self.synchronousLineThreshold {
            rowsView(
                FlattenedDiffPreviewRows.makeRows(
                    files: files,
                    showsFileHeaders: showsFileHeaders,
                    allowsFileCollapse: allowsFileCollapse,
                    collapsedFileIDs: collapsedFileIDs
                )
            )
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
                    let allowsFileCollapse = allowsFileCollapse
                    let collapsedFileIDs = collapsedFileIDs
                    let currentRenderID = currentRenderID
                    preparedRows = []
                    preparedRowsID = nil
                    let rowTask = Task.detached(priority: .userInitiated) {
                        try FlattenedDiffPreviewRows.makeRowsUnlessCancelled(
                            files: files,
                            showsFileHeaders: showsFileHeaders,
                            allowsFileCollapse: allowsFileCollapse,
                            collapsedFileIDs: collapsedFileIDs
                        )
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
                    FlattenedDiffPreviewRenderRow(
                        row: row,
                        allowsFileCollapse: allowsFileCollapse,
                        collapsedFileIDs: collapsedFileIDs,
                        onToggleFileCollapse: onToggleFileCollapse
                    )
                }
            }
            .appExpansionAnimationOverride(value: collapsedFileIDs)
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
        files.enumerated().reduce(0) { total, entry in
            let (fileIndex, file) = entry
            if isFileCollapsed(file, fileIndex: fileIndex) {
                return total
            }

            return total + file.hunks.reduce(0) { $0 + $1.lines.count }
        }
    }

    private var renderFingerprint: Int {
        // Include line content so a large diff cannot reuse prepared rows from
        // another diff with the same file paths and hunk shape.
        var hasher = Hasher()
        hasher.combine(showsFileHeaders)
        hasher.combine(allowsFileCollapse)
        if allowsFileCollapse {
            for collapsedFileID in collapsedFileIDs.sorted() {
                hasher.combine(collapsedFileID)
            }
        }
        for (fileIndex, file) in files.enumerated() {
            hasher.combine(file.oldPath)
            hasher.combine(file.newPath)
            hasher.combine(file.isBinary)
            hasher.combine(file.isRenamed)
            if isFileCollapsed(file, fileIndex: fileIndex) {
                // Collapsed headers still show counts, but hidden line content should not
                // force large prepared previews to rebuild.
                hasher.combine(file.linesAdded)
                hasher.combine(file.linesDeleted)
                continue
            }

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

    private func isFileCollapsed(_ file: DiffFile, fileIndex: Int) -> Bool {
        showsFileHeaders
            && allowsFileCollapse
            && collapsedFileIDs.contains(FlattenedDiffPreviewRows.fileCollapseID(for: file, fileIndex: fileIndex))
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
    private static let expandedFileBottomPadding: CGFloat = 12

    static func makeRows(
        files: [DiffFile],
        showsFileHeaders: Bool,
        allowsFileCollapse: Bool,
        collapsedFileIDs: Set<String>
    ) -> [FlattenedDiffPreviewRow] {
        (try? makeRows(
            files: files,
            showsFileHeaders: showsFileHeaders,
            allowsFileCollapse: allowsFileCollapse,
            collapsedFileIDs: collapsedFileIDs,
            checksCancellation: false
        )) ?? []
    }

    static func makeRowsUnlessCancelled(
        files: [DiffFile],
        showsFileHeaders: Bool,
        allowsFileCollapse: Bool,
        collapsedFileIDs: Set<String>
    ) throws -> [FlattenedDiffPreviewRow] {
        try makeRows(
            files: files,
            showsFileHeaders: showsFileHeaders,
            allowsFileCollapse: allowsFileCollapse,
            collapsedFileIDs: collapsedFileIDs,
            checksCancellation: true
        )
    }

    private static func makeRows(
        files: [DiffFile],
        showsFileHeaders: Bool,
        allowsFileCollapse: Bool,
        collapsedFileIDs: Set<String>,
        checksCancellation: Bool
    ) throws -> [FlattenedDiffPreviewRow] {
        // Keep diff rows flat so LazyVStack can virtualize individual line rows instead of whole hunks.
        var allRows: [FlattenedDiffPreviewRow] = []
        for (fileIndex, file) in files.enumerated() {
            try checkCancellationIfNeeded(checksCancellation)
            var rows: [FlattenedDiffPreviewRow] = []
            let fileID = fileCollapseID(for: file, fileIndex: fileIndex)
            if showsFileHeaders {
                rows.append(
                    .fileHeader(
                        id: "file-\(fileIndex)-header",
                        fileID: fileID,
                        file: file,
                        topPadding: 0
                    )
                )
            }

            if showsFileHeaders,
               allowsFileCollapse,
               collapsedFileIDs.contains(fileID) {
                // Collapsed commit files still emit their header row so the preview
                // remains one flat lazy row stream instead of nesting per-file stacks.
                allRows.append(contentsOf: rows)
                continue
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
            if showsFileHeaders {
                rows.append(.fileContentSpacer(id: "file-\(fileIndex)-bottom-spacer", height: Self.expandedFileBottomPadding))
            }

            allRows.append(contentsOf: rows)
        }

        return allRows
    }

    static func fileCollapseID(for file: DiffFile, fileIndex: Int) -> String {
        let path = file.newPath ?? file.oldPath ?? file.path
        return "\(fileIndex):\(path)"
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
    case fileHeader(id: String, fileID: String, file: DiffFile, topPadding: CGFloat)
    case renameSummary(id: String, oldPath: String, newPath: String)
    case binaryCallout(id: String)
    case emptyCallout(id: String, isRenamed: Bool)
    case hunkHeader(id: String, hunk: DiffHunk, topPadding: CGFloat)
    case line(id: String, line: DiffLine, gutterLayout: DiffGutterLayout, isLastInHunk: Bool, bottomPadding: CGFloat)
    case collapsed(id: String, summary: CollapsedContextSummary, gutterLayout: DiffGutterLayout, isLastInHunk: Bool, bottomPadding: CGFloat)
    case fileContentSpacer(id: String, height: CGFloat)

    var id: String {
        switch self {
        case .fileHeader(let id, _, _, _),
             .renameSummary(let id, _, _),
             .binaryCallout(let id),
             .emptyCallout(let id, _),
             .hunkHeader(let id, _, _),
             .line(let id, _, _, _, _),
             .collapsed(let id, _, _, _, _),
             .fileContentSpacer(let id, _):
            return id
        }
    }
}

private struct FlattenedDiffPreviewRenderRow: View {
    let row: FlattenedDiffPreviewRow
    let allowsFileCollapse: Bool
    let collapsedFileIDs: Set<String>
    let onToggleFileCollapse: (String) -> Void

    var body: some View {
        switch row {
        case .fileHeader(_, let fileID, let file, let topPadding):
            let collapseState = collapseState(for: fileID)
            DiffPreviewFileHeader(
                file: file,
                collapseState: collapseState
            )
                .padding(.top, topPadding)
                .padding(.bottom, collapseState?.isCollapsed == true ? 4 : 10)
                .zIndex(1)
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
        case .fileContentSpacer(_, let height):
            Color.clear
                .frame(height: height)
        }
    }

    private func collapseState(for fileID: String) -> DiffPreviewFileHeaderCollapseState? {
        guard allowsFileCollapse else {
            return nil
        }

        return DiffPreviewFileHeaderCollapseState(
            isCollapsed: collapsedFileIDs.contains(fileID),
            onToggle: {
                withAnimation(appExpansionAnimation) {
                    onToggleFileCollapse(fileID)
                }
            }
        )
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
