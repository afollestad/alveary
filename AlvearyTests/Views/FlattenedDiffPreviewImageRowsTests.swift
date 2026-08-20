import XCTest

@testable import Alveary

/// The row stream's side of pull request image rendering: supplying a preview for a Git LFS file has
/// to *replace* its pointer lines, and supplying none has to leave the diff viewer's stream alone.
final class FlattenedDiffPreviewImageRowsTests: XCTestCase {
    private static let oid = "e908b5e52be4ecc4d05c38ad7afa27021fbb7472ff2d8eae58ae95fd0aca806a"

    private let pointerDiff = """
    diff --git a/assets/hero.png b/assets/hero.png
    new file mode 100644
    index 0000000..abbe130
    --- /dev/null
    +++ b/assets/hero.png
    @@ -0,0 +1,3 @@
    +version https://git-lfs.github.com/spec/v1
    +oid sha256:e908b5e52be4ecc4d05c38ad7afa27021fbb7472ff2d8eae58ae95fd0aca806a
    +size 166854
    """

    private func rows(imagePreviews: [String: DiffImagePreview]) -> [FlattenedDiffPreviewRow] {
        FlattenedDiffPreviewRows.makeRows(
            files: DiffParser.parse(pointerDiff),
            imagePreviews: imagePreviews,
            showsFileHeaders: true,
            allowsFileCollapse: false,
            collapsedFileIDs: []
        ).rows
    }

    private func pullRequestPreviews() -> [String: DiffImagePreview] {
        DiffImagePreviewSupport.pullRequestPreviews(
            for: DiffParser.parse(pointerDiff),
            owner: "octo",
            repo: "demo",
            headRef: "head123",
            baseRef: "base123"
        )
    }

    func testAnLFSPointerBecomesAnImageRowInsteadOfItsPointerLines() throws {
        let previews = pullRequestPreviews()
        XCTAssertEqual(previews.count, 1, "The pointer file should be previewable")

        let rows = rows(imagePreviews: previews)

        XCTAssertTrue(rows.contains { if case .imagePreview = $0 { return true } else { return false } })
        XCTAssertFalse(
            rows.contains { if case .line = $0 { return true } else { return false } },
            "The three pointer lines must not render beside the image"
        )
        XCTAssertFalse(rows.contains { if case .hunkHeader = $0 { return true } else { return false } })
    }

    /// The diff viewer drives this same view inert, and must keep showing the raw pointer text
    /// rather than inheriting the pull request pane's image rows.
    func testWithoutAPreviewThePointerLinesStillRender() {
        let rows = rows(imagePreviews: [:])

        XCTAssertFalse(rows.contains { if case .imagePreview = $0 { return true } else { return false } })
        let lineCount = rows.filter { if case .line = $0 { return true } else { return false } }.count
        XCTAssertEqual(lineCount, 3)
    }

    /// A pointer file is a text diff, so nothing here may depend on `isBinary`.
    func testAnLFSPointerIsNotABinaryDiff() throws {
        let file = try XCTUnwrap(DiffParser.parse(pointerDiff).first)
        XCTAssertFalse(file.isBinary)
        XCTAssertFalse(rows(imagePreviews: [:]).contains {
            if case .binaryCallout = $0 { return true } else { return false }
        })
    }

    func testImageRowsContributeNoScrollableWidth() {
        let prepared = FlattenedDiffPreviewRows.makeRows(
            files: DiffParser.parse(pointerDiff),
            imagePreviews: pullRequestPreviews(),
            showsFileHeaders: true,
            allowsFileCollapse: false,
            collapsedFileIDs: []
        )
        // Per the scope's rule, a row contributing 0 clamps itself to the viewport instead.
        XCTAssertEqual(prepared.minimumScrollableContentWidth, 0)
    }
}
