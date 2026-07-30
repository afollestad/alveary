import XCTest

@testable import Alveary

final class PullRequestDiffFilePagingTests: XCTestCase {
    func testRenderedFilesReturnsPrefixWindow() {
        let files = DiffParser.parse(makeUnifiedDiffFixture(fileCount: 5))

        XCTAssertEqual(PullRequestDiffFilePaging.renderedFiles(files, renderedFileCount: 2).count, 2)
        XCTAssertEqual(PullRequestDiffFilePaging.renderedFiles(files, renderedFileCount: 10).count, 5)
        XCTAssertEqual(PullRequestDiffFilePaging.renderedFiles(files, renderedFileCount: -1).count, 0)
    }

    func testRemainingFileCountClampsAtZero() {
        XCTAssertEqual(PullRequestDiffFilePaging.remainingFileCount(total: 20, renderedFileCount: 15), 5)
        XCTAssertEqual(PullRequestDiffFilePaging.remainingFileCount(total: 10, renderedFileCount: 15), 0)
        XCTAssertEqual(PullRequestDiffFilePaging.remainingFileCount(total: 10, renderedFileCount: -5), 10)
    }

    func testNextRenderedFileCountStepsAndClamps() {
        XCTAssertEqual(PullRequestDiffFilePaging.nextRenderedFileCount(current: 15, total: 40), 30)
        XCTAssertEqual(PullRequestDiffFilePaging.nextRenderedFileCount(current: 30, total: 40), 40)
        XCTAssertEqual(PullRequestDiffFilePaging.nextRenderedFileCount(current: 40, total: 40), 40)
    }

    func testAutoCollapsedFileIDsSelectsOnlyOversizedFiles() {
        let raw = makeUnifiedDiffFixture(fileCount: 1, addedLinesPerFile: 401)
            + makeUnifiedDiffFixture(fileCount: 2, addedLinesPerFile: 3)
        let files = DiffParser.parse(raw)
        XCTAssertEqual(files.count, 3)

        let collapsed = PullRequestDiffFilePaging.autoCollapsedFileIDs(for: files)

        XCTAssertEqual(collapsed.count, 1)
        XCTAssertEqual(
            collapsed.first,
            FlattenedDiffPreviewRows.fileCollapseID(for: files[0], fileIndex: 0)
        )
    }
}
