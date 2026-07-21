import XCTest

@testable import Alveary

@MainActor
extension DiffViewerViewModelTests {
    func testPlainSelectionReplacesSelectionAndPreviewsFile() async {
        let first = FileStatus(path: "one.swift", originalPath: nil, status: .modified, isStaged: false)
        let second = FileStatus(path: "two.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([first, second])],
                diffResults: [
                    Self.modifiedDiff(path: first.path),
                    Self.modifiedDiff(path: second.path)
                ]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])
        await fixture.viewModel.selectFile(first, in: fixture.directory)
        await fixture.viewModel.selectFile(second, in: fixture.directory)

        XCTAssertEqual(fixture.viewModel.selectedFiles, [second])
        XCTAssertEqual(fixture.viewModel.selectedFile, second)
    }

    func testCommandToggleAddsAndRemovesSelection() async {
        let first = FileStatus(path: "one.swift", originalPath: nil, status: .modified, isStaged: false)
        let second = FileStatus(path: "two.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([first, second])],
                diffResults: [
                    Self.modifiedDiff(path: first.path),
                    Self.modifiedDiff(path: second.path),
                    Self.modifiedDiff(path: first.path)
                ]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])
        await fixture.viewModel.selectFile(first, in: fixture.directory)
        await fixture.viewModel.selectFile(second, in: fixture.directory, behavior: .toggle)

        XCTAssertEqual(fixture.viewModel.selectedFiles, [first, second])
        XCTAssertEqual(fixture.viewModel.selectedFile, second)

        await fixture.viewModel.selectFile(second, in: fixture.directory, behavior: .toggle)

        XCTAssertEqual(fixture.viewModel.selectedFiles, [first])
        XCTAssertEqual(fixture.viewModel.selectedFile, first)
    }

    func testShiftRangeSelectionUsesAnchor() async {
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
                    Self.modifiedDiff(path: files[2].path)
                ]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])
        await fixture.viewModel.selectFile(files[0], in: fixture.directory)
        await fixture.viewModel.selectFile(files[2], in: fixture.directory, behavior: .range)

        XCTAssertEqual(fixture.viewModel.selectedFiles, files)
        XCTAssertEqual(fixture.viewModel.selectedFile, files[2])
    }

    func testCommandShiftRangeUnionsWithExistingSelection() async {
        let files = [
            FileStatus(path: "one.swift", originalPath: nil, status: .modified, isStaged: false),
            FileStatus(path: "two.swift", originalPath: nil, status: .modified, isStaged: false),
            FileStatus(path: "three.swift", originalPath: nil, status: .modified, isStaged: false),
            FileStatus(path: "four.swift", originalPath: nil, status: .modified, isStaged: false)
        ]
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success(files)],
                diffResults: [
                    Self.modifiedDiff(path: files[1].path),
                    Self.modifiedDiff(path: files[3].path),
                    Self.modifiedDiff(path: files[2].path)
                ]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])
        await fixture.viewModel.selectFile(files[1], in: fixture.directory)
        await fixture.viewModel.selectFile(files[3], in: fixture.directory, behavior: .toggle)
        await fixture.viewModel.selectFile(files[2], in: fixture.directory, behavior: .rangeUnion)

        XCTAssertEqual(fixture.viewModel.selectedFiles, Array(files[1...3]))
        XCTAssertEqual(fixture.viewModel.selectedFile, files[2])
    }

    func testSelectAllFilesSelectsEveryVisibleFileAndInitializesPreviewAnchor() async {
        let files = [
            FileStatus(path: "one.swift", originalPath: nil, status: .modified, isStaged: false),
            FileStatus(path: "two.swift", originalPath: nil, status: .modified, isStaged: false)
        ]
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success(files)],
                diffResults: [Self.modifiedDiff(path: files[0].path)]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])

        await fixture.viewModel.selectAllFiles(in: fixture.directory)

        XCTAssertEqual(fixture.viewModel.selectedFiles, files)
        XCTAssertEqual(fixture.viewModel.selectedFile, files[0])
        XCTAssertEqual(fixture.viewModel.parsedDiff?.path, files[0].path)
    }

    func testSelectAllFilesPreservesExistingPreviewAnchor() async {
        let files = [
            FileStatus(path: "one.swift", originalPath: nil, status: .modified, isStaged: false),
            FileStatus(path: "two.swift", originalPath: nil, status: .modified, isStaged: false),
            FileStatus(path: "three.swift", originalPath: nil, status: .modified, isStaged: false)
        ]
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success(files)],
                diffResults: [Self.modifiedDiff(path: files[1].path)]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])
        await fixture.viewModel.selectFile(files[1], in: fixture.directory)

        await fixture.viewModel.selectAllFiles(in: fixture.directory)

        XCTAssertEqual(fixture.viewModel.selectedFiles, files)
        XCTAssertEqual(fixture.viewModel.selectedFile, files[1])
        XCTAssertEqual(fixture.viewModel.parsedDiff?.path, files[1].path)

        let diffCalls = await fixture.gitService.diffCalls()
        XCTAssertEqual(diffCalls.map(\.paths), [[files[1].path]])
    }

    func testSelectAllFilesIsNoOpForEmptyList() async {
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(statusResults: [.success([])])
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])

        await fixture.viewModel.selectAllFiles(in: fixture.directory)

        XCTAssertTrue(fixture.viewModel.selectedFiles.isEmpty)
        XCTAssertNil(fixture.viewModel.selectedFile)
    }

    func testKeyboardNavigationMovesSelectedFileAndLoadsDiff() async {
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
                    Self.modifiedDiff(path: files[0].path)
                ]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])
        await fixture.viewModel.selectFile(files[0], in: fixture.directory)

        await fixture.viewModel.selectAdjacentFile(forward: true)

        XCTAssertEqual(fixture.viewModel.selectedFiles, [files[1]])
        XCTAssertEqual(fixture.viewModel.selectedFile, files[1])
        XCTAssertEqual(fixture.viewModel.parsedDiff?.path, files[1].path)

        await fixture.viewModel.selectAdjacentFile(forward: false)

        XCTAssertEqual(fixture.viewModel.selectedFiles, [files[0]])
        XCTAssertEqual(fixture.viewModel.selectedFile, files[0])
        XCTAssertEqual(fixture.viewModel.parsedDiff?.path, files[0].path)
    }

    func testAdjacentFileUsesImmediateSelectionBeforePreviewLoad() async {
        let files = [
            FileStatus(path: "one.swift", originalPath: nil, status: .modified, isStaged: false),
            FileStatus(path: "two.swift", originalPath: nil, status: .modified, isStaged: false),
            FileStatus(path: "three.swift", originalPath: nil, status: .modified, isStaged: false)
        ]
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success(files)],
                diffResults: [Self.modifiedDiff(path: files[0].path)]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])
        await fixture.viewModel.selectFile(files[0], in: fixture.directory)

        XCTAssertNotNil(fixture.viewModel.selectFileImmediately(files[1], in: fixture.directory, behavior: .single))

        XCTAssertEqual(fixture.viewModel.selectedFiles, [files[1]])
        XCTAssertEqual(fixture.viewModel.selectedFile, files[0])
        XCTAssertEqual(fixture.viewModel.adjacentFile(forward: true), files[2])
        XCTAssertEqual(fixture.viewModel.adjacentFile(forward: false), files[0])
    }

    func testKeyboardNavigationSelectsFirstFileFromNoSelectionOnlyWhenMovingDown() async {
        let files = [
            FileStatus(path: "one.swift", originalPath: nil, status: .modified, isStaged: false),
            FileStatus(path: "two.swift", originalPath: nil, status: .modified, isStaged: false)
        ]
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success(files)],
                diffResults: [Self.modifiedDiff(path: files[0].path)]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])

        await fixture.viewModel.selectAdjacentFile(forward: false)

        XCTAssertTrue(fixture.viewModel.selectedFiles.isEmpty)
        XCTAssertNil(fixture.viewModel.selectedFile)

        await fixture.viewModel.selectAdjacentFile(forward: true)

        XCTAssertEqual(fixture.viewModel.selectedFiles, [files[0]])
        XCTAssertEqual(fixture.viewModel.selectedFile, files[0])
        XCTAssertEqual(fixture.viewModel.parsedDiff?.path, files[0].path)
    }

    func testKeyboardNavigationAtFileBoundsDoesNotChangeSelection() async {
        let files = [
            FileStatus(path: "one.swift", originalPath: nil, status: .modified, isStaged: false),
            FileStatus(path: "two.swift", originalPath: nil, status: .modified, isStaged: false)
        ]
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success(files)],
                diffResults: [
                    Self.modifiedDiff(path: files[0].path),
                    Self.modifiedDiff(path: files[1].path)
                ]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])
        await fixture.viewModel.selectFile(files[0], in: fixture.directory)

        await fixture.viewModel.selectAdjacentFile(forward: false)

        XCTAssertEqual(fixture.viewModel.selectedFiles, [files[0]])
        XCTAssertEqual(fixture.viewModel.selectedFile, files[0])

        await fixture.viewModel.selectFile(files[1], in: fixture.directory)
        await fixture.viewModel.selectAdjacentFile(forward: true)

        XCTAssertEqual(fixture.viewModel.selectedFiles, [files[1]])
        XCTAssertEqual(fixture.viewModel.selectedFile, files[1])

        let diffCalls = await fixture.gitService.diffCalls()
        XCTAssertEqual(diffCalls.map(\.paths), [[files[0].path], [files[1].path]])
    }

    func testKeyboardNavigationAfterMultiSelectionUsesPreviewAnchorAndClearsMultiSelection() async {
        let files = [
            FileStatus(path: "one.swift", originalPath: nil, status: .modified, isStaged: false),
            FileStatus(path: "two.swift", originalPath: nil, status: .modified, isStaged: false),
            FileStatus(path: "three.swift", originalPath: nil, status: .modified, isStaged: false),
            FileStatus(path: "four.swift", originalPath: nil, status: .modified, isStaged: false)
        ]
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success(files)],
                diffResults: [
                    Self.modifiedDiff(path: files[0].path),
                    Self.modifiedDiff(path: files[2].path),
                    Self.modifiedDiff(path: files[1].path)
                ]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])
        await fixture.viewModel.selectFile(files[0], in: fixture.directory)
        await fixture.viewModel.selectFile(files[2], in: fixture.directory, behavior: .toggle)

        await fixture.viewModel.selectAdjacentFile(forward: false)

        XCTAssertEqual(fixture.viewModel.selectedFiles, [files[1]])
        XCTAssertEqual(fixture.viewModel.selectedFile, files[1])
        XCTAssertEqual(fixture.viewModel.parsedDiff?.path, files[1].path)
    }

    func testRefreshPrunesSelectionToRemainingFiles() async {
        let first = FileStatus(path: "one.swift", originalPath: nil, status: .modified, isStaged: false)
        let second = FileStatus(path: "two.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([first, second]), .success([first])],
                diffResults: [
                    Self.modifiedDiff(path: first.path),
                    Self.modifiedDiff(path: second.path),
                    Self.modifiedDiff(path: first.path)
                ]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])
        await fixture.viewModel.selectFile(first, in: fixture.directory)
        await fixture.viewModel.selectFile(second, in: fixture.directory, behavior: .toggle)
        await fixture.viewModel.refresh(in: fixture.directory, reason: .manual)

        XCTAssertEqual(fixture.viewModel.selectedFiles, [first])
        XCTAssertEqual(fixture.viewModel.selectedFile, first)
    }

    func testNonGitRefreshClearsMultiSelection() async {
        let file = FileStatus(path: "one.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([file]), .failure(GitError.notARepository)],
                diffResults: [Self.modifiedDiff(path: file.path)]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])
        await fixture.viewModel.selectFile(file, in: fixture.directory)
        await fixture.viewModel.refresh(in: fixture.directory, reason: .manual)

        XCTAssertTrue(fixture.viewModel.selectedFiles.isEmpty)
        XCTAssertNil(fixture.viewModel.selectedFile)
    }

    func testStatusErrorRefreshClearsMultiSelection() async {
        let file = FileStatus(path: "one.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([file]), .failure(GitError.commandFailed("fatal"))],
                diffResults: [Self.modifiedDiff(path: file.path)]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])
        await fixture.viewModel.selectFile(file, in: fixture.directory)
        await fixture.viewModel.refresh(in: fixture.directory, reason: .manual)

        XCTAssertTrue(fixture.viewModel.selectedFiles.isEmpty)
        XCTAssertNil(fixture.viewModel.selectedFile)
    }

    func testTargetSwitchClearsMultiSelection() async {
        let file = FileStatus(path: "one.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([file]), .success([])],
                diffResults: [Self.modifiedDiff(path: file.path)]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])
        await fixture.viewModel.selectFile(file, in: fixture.directory)
        await fixture.viewModel.switchToDirectory("/tmp/other-alveary-project", baseRef: "main", remoteName: nil, conversationIds: [])

        XCTAssertTrue(fixture.viewModel.selectedFiles.isEmpty)
        XCTAssertNil(fixture.viewModel.selectedFile)
    }

    func testBatchStageAndUnstageUseOnlyApplicableSelections() async throws {
        let unstaged = FileStatus(path: "one.swift", originalPath: nil, status: .modified, isStaged: false)
        let staged = FileStatus(path: "two.swift", originalPath: nil, status: .modified, isStaged: true)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([unstaged, staged]), .success([unstaged, staged]), .success([unstaged, staged])],
                diffResults: [
                    Self.modifiedDiff(path: unstaged.path),
                    Self.modifiedDiff(path: staged.path)
                ]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])
        await fixture.viewModel.selectFile(unstaged, in: fixture.directory)
        await fixture.viewModel.selectFile(staged, in: fixture.directory, behavior: .toggle)

        try await fixture.viewModel.stage(files: fixture.viewModel.selectedFiles.filter { !$0.isStaged }, in: fixture.directory)
        try await fixture.viewModel.unstage(files: fixture.viewModel.selectedFiles.filter(\.isStaged), in: fixture.directory)

        let stageCalls = await fixture.gitService.stageCalls()
        let unstageCalls = await fixture.gitService.unstageCalls()
        XCTAssertEqual(stageCalls, [.init(paths: [unstaged.path], directory: fixture.directory)])
        XCTAssertEqual(unstageCalls, [.init(paths: [staged.path], directory: fixture.directory)])
    }

    func testBatchStageAndUnstagePreserveMovedSelection() async throws {
        let unstagedFiles = [
            FileStatus(path: "one.swift", originalPath: nil, status: .modified, isStaged: false),
            FileStatus(path: "two.swift", originalPath: nil, status: .modified, isStaged: false)
        ]
        let stagedFiles = unstagedFiles.map {
            FileStatus(path: $0.path, originalPath: nil, status: .modified, isStaged: true)
        }
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success(unstagedFiles), .success(stagedFiles), .success(unstagedFiles)],
                diffResults: [
                    Self.modifiedDiff(path: unstagedFiles[0].path),
                    Self.modifiedDiff(path: unstagedFiles[1].path),
                    Self.modifiedDiff(path: stagedFiles[1].path),
                    Self.modifiedDiff(path: unstagedFiles[1].path)
                ]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])
        fixture.viewModel.setWatchingEnabled(true)
        await fixture.viewModel.selectFile(unstagedFiles[0], in: fixture.directory)
        await fixture.viewModel.selectFile(unstagedFiles[1], in: fixture.directory, behavior: .toggle)

        try await fixture.viewModel.stage(files: fixture.viewModel.selectedFiles, in: fixture.directory)

        XCTAssertEqual(fixture.viewModel.selectedFiles, stagedFiles)
        XCTAssertEqual(fixture.viewModel.selectedFile, stagedFiles[1])

        try await fixture.viewModel.unstage(files: fixture.viewModel.selectedFiles, in: fixture.directory)

        XCTAssertEqual(fixture.viewModel.selectedFiles, unstagedFiles)
        XCTAssertEqual(fixture.viewModel.selectedFile, unstagedFiles[1])
    }

    func testDiscardSelectionSplitsStagedAndUnstagedScopes() async throws {
        let renamed = FileStatus(path: "new.swift", originalPath: "old.swift", status: .renamed, isStaged: true)
        let unstaged = FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([renamed, unstaged]), .success([])],
                diffResults: [
                    Self.renameDiff(from: "old.swift", to: "new.swift"),
                    Self.modifiedDiff(path: unstaged.path)
                ]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, baseRef: "main", remoteName: nil, conversationIds: [])
        await fixture.viewModel.selectFile(renamed, in: fixture.directory)
        await fixture.viewModel.selectFile(unstaged, in: fixture.directory, behavior: .toggle)

        try await fixture.viewModel.discard(files: fixture.viewModel.selectedFiles, in: fixture.directory)

        let discardCalls = await fixture.gitService.discardCalls()
        XCTAssertEqual(discardCalls, [
            .init(paths: ["old.swift", "new.swift"], scope: .all, directory: fixture.directory),
            .init(paths: ["feature.swift"], scope: .worktreeOnly, directory: fixture.directory)
        ])
    }
}
