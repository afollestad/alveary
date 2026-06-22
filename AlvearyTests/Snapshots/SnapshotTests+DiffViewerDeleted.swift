import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testDiffViewerPaneDeletedFileCompactGutter() async {
        let path = "violet-codex-4509.txt"
        let selectedFile = FileStatus(path: path, originalPath: nil, status: .deleted, isStaged: false)
        let fixture = SnapshotDiffViewerFixture(
            gitService: SnapshotMockGitService(
                statusResults: [[selectedFile]],
                diffResults: [Self.deletedFileDiff(path: path)]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: Set(["main"])
        )
        await fixture.viewModel.selectFile(selectedFile, in: fixture.directory)

        assertMacSnapshot(
            DiffViewerPane(
                viewModel: fixture.viewModel,
                canCommit: true,
                canRequestOpenPR: true,
                onCommitRequested: {},
                onOpenPRRequested: {}
            ),
            size: CGSize(width: 460, height: 520),
            named: "diff_viewer_deleted_compact_gutter"
        )
    }
}
