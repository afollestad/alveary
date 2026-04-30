import XCTest

@testable import Alveary

@MainActor
extension DiffViewerViewModelTests {
    func testSelectedModifiedImageBuildsOldAndNewPreviewSources() async throws {
        let file = FileStatus(path: "Assets/logo.png", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([file])],
                diffResults: [Self.binaryDiff(path: file.path)],
                currentHeadHashResult: .success("head123")
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        await fixture.viewModel.selectFile(file, in: fixture.directory)

        let preview = try XCTUnwrap(fixture.viewModel.imagePreview)
        XCTAssertEqual(preview.old?.source, .index(path: "Assets/logo.png"))
        XCTAssertEqual(preview.old?.identityPrefix, "head123-index")
        XCTAssertEqual(preview.old?.needsContentHash, true)
        XCTAssertEqual(preview.new?.source, .worktree(path: "Assets/logo.png"))
        XCTAssertEqual(preview.new?.identityPrefix, "head123-worktree")
        XCTAssertEqual(preview.new?.needsContentHash, true)
    }

    func testSelectedUntrackedImageBuildsNewPreviewOnly() async throws {
        let file = FileStatus(path: "Assets/new-logo.png", originalPath: nil, status: .untracked, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([file])],
                syntheticDiffResultQueue: [.failure(GitError.outputTooLarge("Untracked file is too large to preview (>100KB)"))],
                currentHeadHashResult: .success("head123")
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        await fixture.viewModel.selectFile(file, in: fixture.directory)

        let preview = try XCTUnwrap(fixture.viewModel.imagePreview)
        XCTAssertNil(preview.old)
        XCTAssertEqual(preview.new?.source, .worktree(path: "Assets/new-logo.png"))
        let syntheticDiffCalls = await fixture.gitService.syntheticDiffCalls()
        XCTAssertEqual(syntheticDiffCalls, ["Assets/new-logo.png"])
    }

    func testSelectedSmallUntrackedTextFileWithImageExtensionUsesTextDiff() async throws {
        let file = FileStatus(path: "Assets/not-really-image.png", originalPath: nil, status: .untracked, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([file])],
                syntheticDiffResults: [Self.addedTextDiff(path: file.path)],
                currentHeadHashResult: .failure(GitError.commandFailed("should not request HEAD"))
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        await fixture.viewModel.selectFile(file, in: fixture.directory)

        XCTAssertNotNil(fixture.viewModel.parsedDiff)
        XCTAssertNil(fixture.viewModel.imagePreview)
        let syntheticDiffCalls = await fixture.gitService.syntheticDiffCalls()
        XCTAssertEqual(syntheticDiffCalls, ["Assets/not-really-image.png"])
        let headHashCalls = await fixture.gitService.currentHeadHashCallCount()
        XCTAssertEqual(headHashCalls, 0)
    }

    func testSelectedStagedAddedImageBuildsIndexPreviewOnly() async throws {
        let file = FileStatus(path: "Assets/new-logo.png", originalPath: nil, status: .added, isStaged: true)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([file])],
                diffResults: [Self.addedBinaryDiff(path: file.path)],
                currentHeadHashResult: .success("head123")
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        await fixture.viewModel.selectFile(file, in: fixture.directory)

        let preview = try XCTUnwrap(fixture.viewModel.imagePreview)
        XCTAssertNil(preview.old)
        XCTAssertEqual(preview.new?.source, .index(path: "Assets/new-logo.png"))
        XCTAssertEqual(preview.new?.identityPrefix, "head123-index")
        XCTAssertEqual(preview.new?.needsContentHash, true)
    }

    func testSelectedDeletedImageBuildsOldPreviewOnly() async throws {
        let file = FileStatus(path: "Assets/removed-logo.png", originalPath: nil, status: .deleted, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([file])],
                diffResults: [Self.deletedBinaryDiff(path: file.path)],
                currentHeadHashResult: .success("head123")
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        await fixture.viewModel.selectFile(file, in: fixture.directory)

        let preview = try XCTUnwrap(fixture.viewModel.imagePreview)
        XCTAssertEqual(preview.old?.source, .index(path: "Assets/removed-logo.png"))
        XCTAssertEqual(preview.old?.identityPrefix, "head123-index")
        XCTAssertEqual(preview.old?.needsContentHash, true)
        XCTAssertNil(preview.new)
    }

    func testSelectedDiffFailureRendersLowerPaneMessageWithoutGlobalGitError() async throws {
        let file = FileStatus(path: "notes.txt", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([file])],
                diffResultQueue: [.failure(GitError.outputTooLarge("Diff preview exceeded 5MB"))]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        await fixture.viewModel.selectFile(file, in: fixture.directory)

        XCTAssertNil(fixture.viewModel.gitError)
        XCTAssertEqual(fixture.viewModel.selectedDiffErrorMessage, "Diff preview exceeded 5MB")
    }

    func testSelectedTextDiffDoesNotRequestHeadHashForImageIdentity() async throws {
        let file = FileStatus(path: "notes.txt", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([file])],
                diffResults: [Self.textDiff(path: file.path)],
                currentHeadHashResult: .failure(GitError.commandFailed("should not request HEAD"))
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        await fixture.viewModel.selectFile(file, in: fixture.directory)

        XCTAssertNotNil(fixture.viewModel.parsedDiff)
        let headHashCalls = await fixture.gitService.currentHeadHashCallCount()
        XCTAssertEqual(headHashCalls, 0)
    }

    func testSelectedTextDiffWithImageExtensionDoesNotBuildImagePreview() async throws {
        let file = FileStatus(path: "Assets/not-really-image.png", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([file])],
                diffResults: [Self.textDiff(path: file.path)],
                currentHeadHashResult: .failure(GitError.commandFailed("should not request HEAD"))
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        await fixture.viewModel.selectFile(file, in: fixture.directory)

        XCTAssertNotNil(fixture.viewModel.parsedDiff)
        XCTAssertNil(fixture.viewModel.imagePreview)
        let headHashCalls = await fixture.gitService.currentHeadHashCallCount()
        XCTAssertEqual(headHashCalls, 0)
    }

    func testCommitDiffBuildsImagePreviewForParsedFileID() async throws {
        let commit = CommitInfo(hash: "abc123", message: "Change logo", author: "A", date: Date())
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                commitsAheadDetailsResults: [.success([commit])],
                commitDiffResults: [.success(Self.binaryDiff(path: "Assets/logo.png"))]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        await fixture.viewModel.loadAheadCommitsForActiveTarget()

        let preview = try XCTUnwrap(fixture.viewModel.commitImagePreviews["0:Assets/logo.png"])
        XCTAssertEqual(preview.old?.source, .commitParent(hash: "abc123", path: "Assets/logo.png"))
        XCTAssertEqual(preview.new?.source, .commit(hash: "abc123", path: "Assets/logo.png"))
    }

    func testCommitDiffBuildsOneSidedImagePreviewsForAddedAndDeletedFiles() async throws {
        let commit = CommitInfo(hash: "abc123", message: "Change images", author: "A", date: Date())
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                commitsAheadDetailsResults: [.success([commit])],
                commitDiffResults: [
                    .success(
                        [
                            Self.addedBinaryDiff(path: "Assets/new-logo.png"),
                            Self.deletedBinaryDiff(path: "Assets/removed-logo.png")
                        ].joined(separator: "\n")
                    )
                ]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        await fixture.viewModel.loadAheadCommitsForActiveTarget()

        let addedPreview = try XCTUnwrap(fixture.viewModel.commitImagePreviews["0:Assets/new-logo.png"])
        XCTAssertNil(addedPreview.old)
        XCTAssertEqual(addedPreview.new?.source, .commit(hash: "abc123", path: "Assets/new-logo.png"))

        let deletedPreview = try XCTUnwrap(fixture.viewModel.commitImagePreviews["1:Assets/removed-logo.png"])
        XCTAssertEqual(deletedPreview.old?.source, .commitParent(hash: "abc123", path: "Assets/removed-logo.png"))
        XCTAssertNil(deletedPreview.new)
    }

    func testCommitTextDiffWithImageExtensionDoesNotBuildImagePreview() async throws {
        let commit = CommitInfo(hash: "abc123", message: "Change text asset", author: "A", date: Date())
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                commitsAheadDetailsResults: [.success([commit])],
                commitDiffResults: [.success(Self.textDiff(path: "Assets/not-really-image.png"))]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        await fixture.viewModel.loadAheadCommitsForActiveTarget()

        XCTAssertEqual(fixture.viewModel.commitDiffFiles.count, 1)
        XCTAssertTrue(fixture.viewModel.commitImagePreviews.isEmpty)
    }

    private static func binaryDiff(path: String) -> String {
        """
        diff --git a/\(path) b/\(path)
        Binary files a/\(path) and b/\(path) differ
        """
    }

    private static func addedBinaryDiff(path: String) -> String {
        """
        diff --git a/\(path) b/\(path)
        new file mode 100644
        Binary files /dev/null and b/\(path) differ
        """
    }

    private static func deletedBinaryDiff(path: String) -> String {
        """
        diff --git a/\(path) b/\(path)
        deleted file mode 100644
        Binary files a/\(path) and /dev/null differ
        """
    }

    private static func addedTextDiff(path: String) -> String {
        """
        diff --git a/\(path) b/\(path)
        new file mode 100644
        --- /dev/null
        +++ b/\(path)
        @@ -0,0 +1,1 @@
        +hello
        """
    }

    private static func textDiff(path: String) -> String {
        """
        diff --git a/\(path) b/\(path)
        --- a/\(path)
        +++ b/\(path)
        @@ -1,1 +1,1 @@
        -old
        +new
        """
    }

}
