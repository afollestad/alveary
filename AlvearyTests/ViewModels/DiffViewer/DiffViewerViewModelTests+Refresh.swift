import XCTest

@testable import Alveary

@MainActor
extension DiffViewerViewModelTests {
    func testForceRefreshActiveDiffReloadsSelectedFileForActiveTarget() async {
        let selectedFile = FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([selectedFile]), .success([selectedFile])],
                diffResults: [
                    Self.modifiedDiff(path: "feature.swift", newLine: "first"),
                    Self.modifiedDiff(path: "feature.swift", newLine: "second")
                ]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )
        await fixture.viewModel.selectFile(selectedFile, in: fixture.directory)

        await fixture.viewModel.forceRefreshActiveDiff()

        let diffCalls = await fixture.gitService.diffCalls()
        XCTAssertEqual(diffCalls.count, 2)
        XCTAssertEqual(diffCalls.last?.directory, fixture.directory)
        XCTAssertEqual(fixture.viewModel.parsedDiff?.hunks.first?.lines.last?.content, "second")
    }
}
