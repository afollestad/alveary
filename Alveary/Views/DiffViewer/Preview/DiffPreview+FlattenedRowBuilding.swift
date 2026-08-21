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
        )) ?? FlattenedDiffPreviewPreparedRows(
            rows: [],
            minimumScrollableContentWidth: 0,
            heightPlan: FlattenedDiffPreviewHeightPlan(),
            collapsedFileIDs: []
        )
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
            let rows = try fileRows(
                file: file,
                fileIndex: fileIndex,
                imagePreviews: imagePreviews,
                showsFileHeaders: showsFileHeaders,
                allowsFileCollapse: allowsFileCollapse,
                collapsedFileIDs: collapsedFileIDs,
                commentAnnotations: commentAnnotations,
                checksCancellation: checksCancellation
            )
            scrollableContentWidth = max(scrollableContentWidth, minimumScrollableContentWidth(for: rows))
            allRows.append(contentsOf: rows)
        }

        return prepared(
            rows: allRows,
            scrollableContentWidth: scrollableContentWidth,
            collapsedFileIDs: showsFileHeaders && allowsFileCollapse ? collapsedFileIDs : []
        )
    }

    // swiftlint:disable:next function_parameter_count
    private static func fileRows(
        file: DiffFile,
        fileIndex: Int,
        imagePreviews: [String: DiffImagePreview],
        showsFileHeaders: Bool,
        allowsFileCollapse: Bool,
        collapsedFileIDs: Set<String>,
        commentAnnotations: DiffCommentAnnotations,
        checksCancellation: Bool
    ) throws -> [FlattenedDiffPreviewRow] {
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
            return rows
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
        return rows
    }

    /// `collapsedFileIDs` is the set the *renderer* will key its measurements with, so a row's
    /// measured height lands under the key the plan counted it as.
    private static func prepared(
        rows: [FlattenedDiffPreviewRow],
        scrollableContentWidth: CGFloat,
        collapsedFileIDs: Set<String>
    ) -> FlattenedDiffPreviewPreparedRows {
        var plan = FlattenedDiffPreviewHeightPlan()
        for row in rows {
            plan.add(row, collapsedFileIDs: collapsedFileIDs)
        }
        return FlattenedDiffPreviewPreparedRows(
            rows: rows,
            minimumScrollableContentWidth: scrollableContentWidth,
            heightPlan: plan,
            collapsedFileIDs: collapsedFileIDs
        )
    }

    static func fileCollapseID(for file: DiffFile, fileIndex: Int) -> String {
        let path = file.newPath ?? file.oldPath ?? file.path
        return "\(fileIndex):\(path)"
    }

    // A line row plus any comment thread and composer rows anchored to it. The
    // hunk-row chrome flags (bottom rounding, inter-hunk padding) belong to the
    // group's final row: a comment row extends the hunk's code surface, so an
    // anchored line must not round or pad above one.
    // swiftlint:disable:next function_parameter_count
    private static func lineRowGroup(
        id: String,
        line: DiffLine,
        gutterLayout: DiffGutterLayout,
        isLastInHunk: Bool,
        bottomPadding: CGFloat,
        commentPath: String,
        commentAnnotations: DiffCommentAnnotations,
        followingLineType: DiffLine.LineType?
    ) -> [FlattenedDiffPreviewRow] {
        let anchor = commentAnnotations.isActive ? commentAnchor(for: line, path: commentPath) : nil
        let thread = anchor.flatMap { commentAnnotations.threads[$0] }
        let showsComposer = anchor != nil && commentAnnotations.composerAnchor == anchor
        let lineIsLast = thread == nil && !showsComposer
        // The composer renders below the thread, so it is the group's last row
        // whenever it is present.
        let threadIsLast = thread != nil && !showsComposer
        // Only the group's final row borders the following line; interior
        // boundaries (thread above a composer) stay the anchored line's tint.
        let trailingWashType = followingLineType ?? line.type

        var rows: [FlattenedDiffPreviewRow] = [
            .line(
                id: id,
                line: line,
                gutterLayout: gutterLayout,
                isLastInHunk: isLastInHunk && lineIsLast,
                bottomPadding: lineIsLast ? bottomPadding : 0,
                commentAnchor: anchor
            )
        ]
        if let anchor {
            if let thread {
                rows.append(.commentThread(
                    id: "comment:\(anchor.key)",
                    thread: thread,
                    anchor: anchor,
                    wash: DiffCommentRowWash(
                        topLineType: line.type,
                        bottomLineType: threadIsLast ? trailingWashType : line.type,
                        gutterLayout: gutterLayout
                    ),
                    isLastInHunk: isLastInHunk && threadIsLast,
                    bottomPadding: threadIsLast ? bottomPadding : 0
                ))
            }
            if showsComposer {
                rows.append(.commentComposer(
                    id: "composer:\(anchor.key)",
                    anchor: anchor,
                    wash: DiffCommentRowWash(
                        topLineType: line.type,
                        bottomLineType: trailingWashType,
                        gutterLayout: gutterLayout
                    ),
                    isLastInHunk: isLastInHunk,
                    bottomPadding: bottomPadding
                ))
            }
        }
        return rows
    }

    /// The next display row's line type, for a comment row's bottom wash band.
    /// An omitted-context row reads as context; past the hunk's end, `nil`.
    private static func followingLineType(
        in displayRows: [DiffHunkDisplayRow],
        after rowIndex: Int
    ) -> DiffLine.LineType? {
        guard displayRows.indices.contains(rowIndex + 1) else {
            return nil
        }
        switch displayRows[rowIndex + 1] {
        case .line(let line):
            return line.type
        case .omitted:
            return .context
        }
    }

    /// Lines that context collapsing must keep visible, because a collapsed line takes its
    /// comment row with it. Empty while the annotations are inert, which is what keeps the
    /// diff viewer's row stream byte-identical.
    private static func collapseExemptAnchors(
        in commentAnnotations: DiffCommentAnnotations
    ) -> Set<DiffCommentAnchor> {
        guard commentAnnotations.isActive else {
            return []
        }
        var anchors = Set(commentAnnotations.threads.keys)
        if let composerAnchor = commentAnnotations.composerAnchor {
            anchors.insert(composerAnchor)
        }
        return anchors
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
        let commentAnchors = collapseExemptAnchors(in: commentAnnotations)
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

            let displayRows = DiffPreviewHunkDisplayRows.makeRows(
                for: hunk,
                commentPath: commentPath,
                commentAnchors: commentAnchors
            )
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
                        commentAnnotations: commentAnnotations,
                        followingLineType: followingLineType(in: displayRows, after: rowIndex)
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
