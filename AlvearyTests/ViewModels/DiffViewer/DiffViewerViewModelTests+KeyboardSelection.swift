import XCTest

@testable import Alveary

@MainActor
extension DiffViewerViewModelTests {
    func testKeyboardRangeNavigationExtendsFileSelection() async {
        let files = [
            FileStatus(path: "one.swift", originalPath: nil, status: .modified, isStaged: false),
            FileStatus(path: "two.swift", originalPath: nil, status: .modified, isStaged: false),
            FileStatus(path: "three.swift", originalPath: nil, status: .modified, isStaged: false)
        ]
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success(files)],
                diffResults: [
                    Self.modifiedDiff(path: files[0].path),
                    Self.modifiedDiff(path: files[1].path),
                    Self.modifiedDiff(path: files[2].path)
                ]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])
        await fixture.viewModel.selectFile(files[0], in: fixture.directory)

        guard let secondFile = fixture.viewModel.adjacentFile(forward: true),
              let secondSelection = fixture.viewModel.selectFileImmediately(secondFile, in: fixture.directory, behavior: .range) else {
            XCTFail("Expected second file range selection")
            return
        }
        await fixture.viewModel.loadSelectedFileDiff(secondSelection)

        XCTAssertEqual(fixture.viewModel.selectedFiles, Array(files[0...1]))
        XCTAssertEqual(fixture.viewModel.selectedFile, files[1])

        guard let thirdFile = fixture.viewModel.adjacentFile(forward: true),
              let thirdSelection = fixture.viewModel.selectFileImmediately(thirdFile, in: fixture.directory, behavior: .range) else {
            XCTFail("Expected third file range selection")
            return
        }
        await fixture.viewModel.loadSelectedFileDiff(thirdSelection)

        XCTAssertEqual(fixture.viewModel.selectedFiles, files)
        XCTAssertEqual(fixture.viewModel.selectedFile, files[2])
        XCTAssertEqual(fixture.viewModel.parsedDiff?.path, files[2].path)
    }
}
