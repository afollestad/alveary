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
