import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testDiffViewerPaneHeaderCurrentChangesDropdown() {
        assertMacSnapshot(
            DiffViewerPaneHeader(
                activeDirectory: "/tmp/alveary",
                mode: .currentChanges,
                contextualAction: .commit,
                selectedFiles: [],
                areAgentActionsEnabled: true,
                showsFileListDivider: false,
                showsFileActions: true,
                onModeSelected: { _ in },
                onCommitRequested: {},
                onOpenPRRequested: {},
                onViewPRRequested: { _ in },
                onStageSelectedFiles: {},
                onUnstageSelectedFiles: {},
                onDiscardSelectedFiles: {}
            ),
            size: CGSize(width: 460, height: 72),
            named: "diff_viewer_header_current_changes_dropdown"
        )
    }

    func testDiffViewerPaneHeaderCommitsDropdownHidesFileActions() {
        assertMacSnapshot(
            DiffViewerPaneHeader(
                activeDirectory: "/tmp/alveary",
                mode: .commits,
                contextualAction: .openPR,
                selectedFiles: [
                    FileStatus(path: "Sources/App.swift", originalPath: nil, status: .modified, isStaged: false)
                ],
                areAgentActionsEnabled: true,
                showsFileListDivider: false,
                showsFileActions: false,
                onModeSelected: { _ in },
                onCommitRequested: {},
                onOpenPRRequested: {},
                onViewPRRequested: { _ in },
                onStageSelectedFiles: {},
                onUnstageSelectedFiles: {},
                onDiscardSelectedFiles: {}
            ),
            size: CGSize(width: 460, height: 72),
            named: "diff_viewer_header_commits_dropdown"
        )
    }

    func testDiffViewerPaneHeaderCommitsDropdownHidesCommitAction() {
        assertMacSnapshot(
            DiffViewerPaneHeader(
                activeDirectory: "/tmp/alveary",
                mode: .commits,
                contextualAction: .commit,
                selectedFiles: [],
                areAgentActionsEnabled: true,
                showsFileListDivider: false,
                showsFileActions: false,
                onModeSelected: { _ in },
                onCommitRequested: {},
                onOpenPRRequested: {},
                onViewPRRequested: { _ in },
                onStageSelectedFiles: {},
                onUnstageSelectedFiles: {},
                onDiscardSelectedFiles: {}
            ),
            size: CGSize(width: 460, height: 72),
            named: "diff_viewer_header_commits_dropdown_no_actions"
        )
    }

    func testDiffViewerPaneHeaderCommitsDropdownShowsViewPRAction() {
        assertMacSnapshot(
            DiffViewerPaneHeader(
                activeDirectory: "/tmp/alveary",
                mode: .commits,
                contextualAction: .viewPR(url: "https://example.com/pull/42"),
                selectedFiles: [],
                areAgentActionsEnabled: true,
                showsFileListDivider: false,
                showsFileActions: false,
                onModeSelected: { _ in },
                onCommitRequested: {},
                onOpenPRRequested: {},
                onViewPRRequested: { _ in },
                onStageSelectedFiles: {},
                onUnstageSelectedFiles: {},
                onDiscardSelectedFiles: {}
            ),
            size: CGSize(width: 460, height: 72),
            named: "diff_viewer_header_commits_dropdown_view_pr"
        )
    }

    func testDiffViewerPaneCurrentChangesMode() async {
        let selectedFile = FileStatus(
            path: "Alveary/Views/Input/ChatInputField.swift",
            originalPath: nil,
            status: .modified,
            isStaged: false
        )
        let fixture = SnapshotDiffViewerFixture(
            gitService: SnapshotMockGitService(
                statusResults: [[selectedFile]],
                diffResults: [Self.modifiedDiff(path: selectedFile.path)]
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
                areAgentActionsEnabled: true,
                mode: .constant(.currentChanges),
                onCommitRequested: {},
                onOpenPRRequested: {}
            ),
            size: CGSize(width: 460, height: 720),
            named: "diff_viewer_mode_current_changes"
        )
    }

    func testDiffViewerPaneCommitsMode() async {
        let commits = [
            Self.commit(hash: "abcdef1234567890", message: "Add diff viewer commit mode")
        ]
        let fixture = SnapshotDiffViewerFixture(
            gitService: SnapshotMockGitService(
                statusResults: [[]],
                diffResults: [],
                aheadCommitResults: [commits, commits],
                commitDiffResults: [
                    Self.modifiedDiff(path: "Alveary/Views/DiffViewer/DiffViewerPane.swift"),
                    Self.modifiedDiff(path: "Alveary/Views/DiffViewer/DiffViewerPane.swift")
                ]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: Set(["main"])
        )
        await fixture.viewModel.loadAheadCommitsForActiveTarget()

        assertMacSnapshot(
            DiffViewerPane(
                viewModel: fixture.viewModel,
                areAgentActionsEnabled: true,
                mode: .constant(.commits),
                onCommitRequested: {},
                onOpenPRRequested: {}
            ),
            size: CGSize(width: 460, height: 720),
            named: "diff_viewer_mode_commits"
        )
    }

    func testDiffViewerPaneCommitsModeEmpty() async {
        let fixture = SnapshotDiffViewerFixture(
            gitService: SnapshotMockGitService(
                statusResults: [[]],
                diffResults: [],
                aheadCommitResults: [[]]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: Set(["main"])
        )
        await fixture.viewModel.loadAheadCommitsForActiveTarget()

        assertMacSnapshot(
            DiffViewerPane(
                viewModel: fixture.viewModel,
                areAgentActionsEnabled: true,
                mode: .constant(.commits),
                onCommitRequested: {},
                onOpenPRRequested: {}
            ),
            size: CGSize(width: 460, height: 520),
            named: "diff_viewer_mode_commits_empty"
        )
    }

    func testDiffViewerPaneCommitRowTruncation() async {
        let commits = [
            Self.commit(
                hash: "abcdef1234567890",
                message: "This commit title is intentionally very long so the row truncates cleanly at the trailing edge"
            )
        ]
        let fixture = SnapshotDiffViewerFixture(
            gitService: SnapshotMockGitService(
                statusResults: [[]],
                diffResults: [],
                aheadCommitResults: [commits, commits],
                commitDiffResults: [
                    Self.modifiedDiff(path: "Alveary/Views/DiffViewer/DiffViewerPane.swift"),
                    Self.modifiedDiff(path: "Alveary/Views/DiffViewer/DiffViewerPane.swift")
                ]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: Set(["main"])
        )
        await fixture.viewModel.loadAheadCommitsForActiveTarget()

        assertMacSnapshot(
            DiffViewerCommitsContent(
                viewModel: fixture.viewModel,
                topSectionFraction: .constant(0.42),
                onTopSectionFractionCommit: { _ in }
            ),
            size: CGSize(width: 260, height: 360),
            named: "diff_viewer_commit_row_truncation"
        )
    }

    private static func commit(hash: String, message: String) -> CommitInfo {
        CommitInfo(hash: hash, message: message, author: "A. Developer", date: Date(timeIntervalSince1970: 1_800_000_000))
    }
}
