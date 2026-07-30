import XCTest

@testable import Alveary

final class FlattenedDiffPreviewCommentRowsTests: XCTestCase {
    private let raw = """
    diff --git a/File.swift b/File.swift
    --- a/File.swift
    +++ b/File.swift
    @@ -10,3 +10,3 @@
     context line
    -deleted line
    +added line
    """

    func testCommentAnchorsMapChangedSides() throws {
        let file = try XCTUnwrap(DiffParser.parse(raw).first)
        let lines = try XCTUnwrap(file.hunks.first).lines
        XCTAssertEqual(lines.map(\.type), [.context, .deleted, .added])

        let contextAnchor = FlattenedDiffPreviewRows.commentAnchor(for: lines[0], path: "File.swift")
        XCTAssertEqual(contextAnchor, DiffCommentAnchor(path: "File.swift", side: .right, line: 10))

        let deletedAnchor = FlattenedDiffPreviewRows.commentAnchor(for: lines[1], path: "File.swift")
        XCTAssertEqual(deletedAnchor, DiffCommentAnchor(path: "File.swift", side: .left, line: 11))

        let addedAnchor = FlattenedDiffPreviewRows.commentAnchor(for: lines[2], path: "File.swift")
        XCTAssertEqual(addedAnchor, DiffCommentAnchor(path: "File.swift", side: .right, line: 11))
    }

    func testNilAnnotationsKeepRowStreamIdentical() {
        let files = DiffParser.parse(raw)
        let baseline = FlattenedDiffPreviewRows.makeRows(
            files: files,
            imagePreviews: [:],
            showsFileHeaders: true,
            allowsFileCollapse: false,
            collapsedFileIDs: []
        )
        let explicitNone = FlattenedDiffPreviewRows.makeRows(
            files: files,
            imagePreviews: [:],
            showsFileHeaders: true,
            allowsFileCollapse: false,
            collapsedFileIDs: [],
            commentAnnotations: .none
        )

        XCTAssertEqual(baseline.rows.map(\.id), explicitNone.rows.map(\.id))
        XCTAssertEqual(baseline.minimumScrollableContentWidth, explicitNone.minimumScrollableContentWidth)
        XCTAssertFalse(baseline.rows.contains { row in
            if case .commentThread = row {
                return true
            }
            if case .commentComposer = row {
                return true
            }
            return false
        })
    }

    func testThreadAndComposerRowsInsertAfterAnchoredLine() {
        let files = DiffParser.parse(raw)
        let addedAnchor = DiffCommentAnchor(path: "File.swift", side: .right, line: 11)
        let deletedAnchor = DiffCommentAnchor(path: "File.swift", side: .left, line: 11)
        var annotations = DiffCommentAnnotations()
        annotations.allowsComposing = true
        annotations.threads[deletedAnchor] = DiffLineCommentThread(
            comments: [DiffLineComment(author: "carol", bodyMarkdown: "Why remove this?", isPending: false)]
        )
        annotations.composerAnchor = addedAnchor

        let prepared = FlattenedDiffPreviewRows.makeRows(
            files: files,
            imagePreviews: [:],
            showsFileHeaders: true,
            allowsFileCollapse: false,
            collapsedFileIDs: [],
            commentAnnotations: annotations
        )
        let ids = prepared.rows.map(\.id)

        guard let deletedLineIndex = ids.firstIndex(of: "file-0-hunk-0-line-1"),
              let addedLineIndex = ids.firstIndex(of: "file-0-hunk-0-line-2") else {
            return XCTFail("Expected line rows for the deleted and added lines in \(ids)")
        }
        XCTAssertEqual(ids[deletedLineIndex + 1], "comment:\(deletedAnchor.key)")
        XCTAssertEqual(ids[addedLineIndex + 1], "composer:\(addedAnchor.key)")
    }

    /// Comment rows extend the hunk's code surface, so the group's final row —
    /// not the anchored line — owns the hunk-end rounding. The added line is the
    /// hunk's last row; with a thread anchored to it, the line must give up
    /// `isLastInHunk` and the thread must take it.
    func testCommentRowAnchoredToTheLastLineTakesOverHunkEndChrome() throws {
        let files = DiffParser.parse(raw)
        let anchor = DiffCommentAnchor(path: "File.swift", side: .right, line: 11)
        var annotations = DiffCommentAnnotations()
        annotations.allowsComposing = true
        annotations.threads[anchor] = DiffLineCommentThread(
            comments: [DiffLineComment(author: "carol", bodyMarkdown: "Last line note", isPending: false)]
        )

        let prepared = FlattenedDiffPreviewRows.makeRows(
            files: files,
            imagePreviews: [:],
            showsFileHeaders: true,
            allowsFileCollapse: false,
            collapsedFileIDs: [],
            commentAnnotations: annotations
        )

        let lineRow = try XCTUnwrap(prepared.rows.first { $0.id == "file-0-hunk-0-line-2" })
        guard case .line(_, _, _, let lineIsLast, _, _) = lineRow else {
            return XCTFail("Expected a line row, got \(lineRow)")
        }
        XCTAssertFalse(lineIsLast)

        let threadRow = try XCTUnwrap(prepared.rows.first { $0.id == "comment:\(anchor.key)" })
        guard case .commentThread(_, _, _, _, let threadIsLast, _) = threadRow else {
            return XCTFail("Expected a comment thread row, got \(threadRow)")
        }
        XCTAssertTrue(threadIsLast)
    }

    /// Comment rows paint wash bands so the neighboring lines' tints pass
    /// through around the floating card: the top band continues the anchored
    /// line, the bottom band the following line — a thread on the deleted line
    /// before the added line mixes red over green. Past the hunk's end the
    /// bottom band falls back to the anchored line's own tint.
    func testCommentRowWashBandsFollowNeighboringLines() throws {
        let files = DiffParser.parse(raw)
        let addedAnchor = DiffCommentAnchor(path: "File.swift", side: .right, line: 11)
        let deletedAnchor = DiffCommentAnchor(path: "File.swift", side: .left, line: 11)
        var annotations = DiffCommentAnnotations()
        annotations.allowsComposing = true
        annotations.threads[deletedAnchor] = DiffLineCommentThread(
            comments: [DiffLineComment(author: "carol", bodyMarkdown: "Why remove this?", isPending: false)]
        )
        annotations.composerAnchor = addedAnchor

        let prepared = FlattenedDiffPreviewRows.makeRows(
            files: files,
            imagePreviews: [:],
            showsFileHeaders: true,
            allowsFileCollapse: false,
            collapsedFileIDs: [],
            commentAnnotations: annotations
        )

        let threadRow = try XCTUnwrap(prepared.rows.first { $0.id == "comment:\(deletedAnchor.key)" })
        guard case .commentThread(_, _, _, let threadWash, _, _) = threadRow else {
            return XCTFail("Expected a comment thread row, got \(threadRow)")
        }
        XCTAssertEqual(threadWash.topLineType, .deleted)
        XCTAssertEqual(threadWash.bottomLineType, .added)

        // The added line is the hunk's last row, so the composer's bottom band
        // has no following line to continue and keeps the anchored tint.
        let composerRow = try XCTUnwrap(prepared.rows.first { $0.id == "composer:\(addedAnchor.key)" })
        guard case .commentComposer(_, _, let composerWash, _, _) = composerRow else {
            return XCTFail("Expected a comment composer row, got \(composerRow)")
        }
        XCTAssertEqual(composerWash.topLineType, .added)
        XCTAssertEqual(composerWash.bottomLineType, .added)
    }

    func testCommentRowsDoNotExtendScrollableContentWidth() {
        let files = DiffParser.parse(raw)
        let anchor = DiffCommentAnchor(path: "File.swift", side: .right, line: 11)
        var annotations = DiffCommentAnnotations()
        annotations.threads[anchor] = DiffLineCommentThread(
            comments: [
                DiffLineComment(
                    author: "carol",
                    bodyMarkdown: String(repeating: "wide comment body ", count: 60),
                    isPending: true
                )
            ]
        )

        let baseline = FlattenedDiffPreviewRows.makeRows(
            files: files,
            imagePreviews: [:],
            showsFileHeaders: true,
            allowsFileCollapse: false,
            collapsedFileIDs: []
        )
        let annotated = FlattenedDiffPreviewRows.makeRows(
            files: files,
            imagePreviews: [:],
            showsFileHeaders: true,
            allowsFileCollapse: false,
            collapsedFileIDs: [],
            commentAnnotations: annotations
        )

        XCTAssertEqual(annotated.minimumScrollableContentWidth, baseline.minimumScrollableContentWidth)
    }
}
