import SwiftUI

// Row-model construction for `FlattenedDiffPreview`; pure and Sendable so large
// diffs can be prepared off the main actor.
enum FlattenedDiffPreviewRows {
    private static let expandedFileBottomPadding: CGFloat = 12

    static func makeRows(
        files: [DiffFile],
        imagePreviews: [String: DiffImagePreview],
        showsFileHeaders: Bool,
        allowsFileCollapse: Bool,
        collapsedFileIDs: Set<String>,
        commentAnnotations: DiffCommentAnnotations = .none
    ) -> FlattenedDiffPreviewPreparedRows {
        (try? makeRows(
            files: files,
            imagePreviews: imagePreviews,
            showsFileHeaders: showsFileHeaders,
            allowsFileCollapse: allowsFileCollapse,
            collapsedFileIDs: collapsedFileIDs,
            commentAnnotations: commentAnnotations,
            checksCancellation: false
        )) ?? FlattenedDiffPreviewPreparedRows(rows: [], minimumScrollableContentWidth: 0)
    }

    static func makeRowsUnlessCancelled(
        files: [DiffFile],
        imagePreviews: [String: DiffImagePreview],
        showsFileHeaders: Bool,
        allowsFileCollapse: Bool,
        collapsedFileIDs: Set<String>,
        commentAnnotations: DiffCommentAnnotations = .none
    ) throws -> FlattenedDiffPreviewPreparedRows {
        try makeRows(
            files: files,
            imagePreviews: imagePreviews,
            showsFileHeaders: showsFileHeaders,
            allowsFileCollapse: allowsFileCollapse,
            collapsedFileIDs: collapsedFileIDs,
            commentAnnotations: commentAnnotations,
            checksCancellation: true
        )
    }

    // swiftlint:disable:next function_parameter_count
    private static func makeRows(
        files: [DiffFile],
        imagePreviews: [String: DiffImagePreview],
        showsFileHeaders: Bool,
        allowsFileCollapse: Bool,
        collapsedFileIDs: Set<String>,
        commentAnnotations: DiffCommentAnnotations,
        checksCancellation: Bool
    ) throws -> FlattenedDiffPreviewPreparedRows {
        // Keep diff rows flat so LazyVStack can virtualize individual line rows instead of whole hunks.
        var allRows: [FlattenedDiffPreviewRow] = []
        var scrollableContentWidth: CGFloat = 0
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
                scrollableContentWidth = max(scrollableContentWidth, minimumScrollableContentWidth(for: rows))
                allRows.append(contentsOf: rows)
                continue
            }

            if file.isRenamed,
               let oldPath = file.oldPath,
               let newPath = file.newPath {
                rows.append(.renameSummary(id: "file-\(fileIndex)-rename", oldPath: oldPath, newPath: newPath))
            }

            if let imagePreview = imagePreviews[fileID] {
                rows.append(.imagePreview(id: "file-\(fileIndex)-image", preview: imagePreview))
            } else if file.isBinary {
                rows.append(.binaryCallout(id: "file-\(fileIndex)-binary"))
            } else if file.hunks.isEmpty {
                rows.append(.emptyCallout(id: "file-\(fileIndex)-empty", isRenamed: file.isRenamed))
            } else {
                rows.append(contentsOf: try hunkRows(
                    for: file,
                    fileIndex: fileIndex,
                    commentAnnotations: commentAnnotations,
                    checksCancellation: checksCancellation
                ))
            }
            if showsFileHeaders {
                rows.append(.fileContentSpacer(id: "file-\(fileIndex)-bottom-spacer", height: Self.expandedFileBottomPadding))
            }

            scrollableContentWidth = max(scrollableContentWidth, minimumScrollableContentWidth(for: rows))
            allRows.append(contentsOf: rows)
        }

        return FlattenedDiffPreviewPreparedRows(rows: allRows, minimumScrollableContentWidth: scrollableContentWidth)
    }

    static func fileCollapseID(for file: DiffFile, fileIndex: Int) -> String {
        let path = file.newPath ?? file.oldPath ?? file.path
        return "\(fileIndex):\(path)"
    }

    // A line row plus any comment thread and composer rows anchored to it.
    // swiftlint:disable:next function_parameter_count
    private static func lineRowGroup(
        id: String,
        line: DiffLine,
        gutterLayout: DiffGutterLayout,
        isLastInHunk: Bool,
        bottomPadding: CGFloat,
        commentPath: String,
        commentAnnotations: DiffCommentAnnotations
    ) -> [FlattenedDiffPreviewRow] {
        let anchor = commentAnnotations.isActive ? commentAnchor(for: line, path: commentPath) : nil
        var rows: [FlattenedDiffPreviewRow] = [
            .line(
                id: id,
                line: line,
                gutterLayout: gutterLayout,
                isLastInHunk: isLastInHunk,
                bottomPadding: bottomPadding,
                commentAnchor: anchor
            )
        ]
        if let anchor {
            if let thread = commentAnnotations.threads[anchor] {
                rows.append(.commentThread(id: "comment:\(anchor.key)", thread: thread, anchor: anchor))
            }
            if commentAnnotations.composerAnchor == anchor {
                rows.append(.commentComposer(id: "composer:\(anchor.key)", anchor: anchor))
            }
        }
        return rows
    }

    /// Maps a diff line to the GitHub review-comment anchor for its changed side:
    /// added and context lines anchor RIGHT on the new line number, deleted lines
    /// anchor LEFT on the old line number.
    static func commentAnchor(for line: DiffLine, path: String) -> DiffCommentAnchor? {
        switch line.type {
        case .added, .context:
            guard let number = line.newLineNumber else {
                return nil
            }
            return DiffCommentAnchor(path: path, side: .right, line: number)
        case .deleted:
            guard let number = line.oldLineNumber else {
                return nil
            }
            return DiffCommentAnchor(path: path, side: .left, line: number)
        }
    }

    private static func hunkRows(
        for file: DiffFile,
        fileIndex: Int,
        commentAnnotations: DiffCommentAnnotations,
        checksCancellation: Bool
    ) throws -> [FlattenedDiffPreviewRow] {
        let lineNumberWidth = lineNumberWidth(for: file)
        let commentPath = file.newPath ?? file.oldPath ?? file.path
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
                    rows.append(contentsOf: lineRowGroup(
                        id: "file-\(fileIndex)-hunk-\(hunkIndex)-line-\(rowIndex)",
                        line: line,
                        gutterLayout: gutterLayout,
                        isLastInHunk: isLastInHunk,
                        bottomPadding: bottomPadding,
                        commentPath: commentPath,
                        commentAnnotations: commentAnnotations
                    ))
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
