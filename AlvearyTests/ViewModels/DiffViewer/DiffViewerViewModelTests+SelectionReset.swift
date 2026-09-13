import XCTest

@testable import Alveary

/// Clearing a workspace must clear stored selection keys and the range-selection anchor.
@MainActor
extension DiffViewerViewModelTests {
    func testNonGitRefreshClearsMultiSelection() async {
        let file = FileStatus(path: "one.swift", originalPath: nil, status: .modified, isStaged: false)
        let second = FileStatus(path: "two.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([file, second]), .failure(GitError.notARepository)],
                diffResults: [Self.modifiedDiff(path: file.path), Self.modifiedDiff(path: second.path)]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])
        await fixture.viewModel.selectFile(file, in: fixture.directory)
        await fixture.viewModel.selectFile(second, in: fixture.directory, behavior: .toggle)
        XCTAssertEqual(fixture.viewModel.selectedFiles, [file, second])
        XCTAssertEqual(fixture.viewModel.selectedFile, second)
        XCTAssertEqual(fixture.viewModel.diffStore.selectedFileKeys, Set([file, second].map(DiffViewerFileSelectionKey.init)))
        XCTAssertEqual(fixture.viewModel.diffStore.selectionAnchorKey, DiffViewerFileSelectionKey(second))
        await fixture.viewModel.refresh(in: fixture.directory, reason: .manual)

        XCTAssertTrue(fixture.viewModel.selectedFiles.isEmpty)
        XCTAssertNil(fixture.viewModel.selectedFile)
        XCTAssertTrue(fixture.viewModel.diffStore.selectedFileKeys.isEmpty)
        XCTAssertNil(fixture.viewModel.diffStore.selectionAnchorKey)
    }

    func testStatusErrorRefreshClearsMultiSelection() async {
        let file = FileStatus(path: "one.swift", originalPath: nil, status: .modified, isStaged: false)
        let second = FileStatus(path: "two.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([file, second]), .failure(GitError.commandFailed("fatal"))],
                diffResults: [Self.modifiedDiff(path: file.path), Self.modifiedDiff(path: second.path)]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])
        await fixture.viewModel.selectFile(file, in: fixture.directory)
        await fixture.viewModel.selectFile(second, in: fixture.directory, behavior: .toggle)
        XCTAssertEqual(fixture.viewModel.selectedFiles, [file, second])
        XCTAssertEqual(fixture.viewModel.selectedFile, second)
        XCTAssertEqual(fixture.viewModel.diffStore.selectedFileKeys, Set([file, second].map(DiffViewerFileSelectionKey.init)))
        XCTAssertEqual(fixture.viewModel.diffStore.selectionAnchorKey, DiffViewerFileSelectionKey(second))
        await fixture.viewModel.refresh(in: fixture.directory, reason: .manual)

        XCTAssertTrue(fixture.viewModel.selectedFiles.isEmpty)
        XCTAssertNil(fixture.viewModel.selectedFile)
        XCTAssertTrue(fixture.viewModel.diffStore.selectedFileKeys.isEmpty)
        XCTAssertNil(fixture.viewModel.diffStore.selectionAnchorKey)
    }

    func testTargetSwitchClearsMultiSelection() async {
        let file = FileStatus(path: "one.swift", originalPath: nil, status: .modified, isStaged: false)
        let second = FileStatus(path: "two.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([file, second]), .success([])],
                diffResults: [Self.modifiedDiff(path: file.path), Self.modifiedDiff(path: second.path)]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])
        await fixture.viewModel.selectFile(file, in: fixture.directory)
        await fixture.viewModel.selectFile(second, in: fixture.directory, behavior: .toggle)
        XCTAssertEqual(fixture.viewModel.selectedFiles, [file, second])
        XCTAssertEqual(fixture.viewModel.selectedFile, second)
        XCTAssertEqual(fixture.viewModel.diffStore.selectedFileKeys, Set([file, second].map(DiffViewerFileSelectionKey.init)))
        XCTAssertEqual(fixture.viewModel.diffStore.selectionAnchorKey, DiffViewerFileSelectionKey(second))
        await fixture.viewModel.switchToDirectory("/tmp/other-alveary-project", baseRef: "main", remoteName: nil, conversationIds: [])

        XCTAssertTrue(fixture.viewModel.selectedFiles.isEmpty)
        XCTAssertNil(fixture.viewModel.selectedFile)
        XCTAssertTrue(fixture.viewModel.diffStore.selectedFileKeys.isEmpty)
        XCTAssertNil(fixture.viewModel.diffStore.selectionAnchorKey)
    }
}
