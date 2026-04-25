import XCTest
import SwiftUI

@testable import Alveary

extension SnapshotTests {
    func testDiffViewerToolbarButtonEmptyStats() {
        assertMacSnapshot(
            DiffViewerToolbarButton(diffStats: .empty, action: {})
                .padding(12),
            size: CGSize(width: 120, height: 56),
            named: "diff_viewer_toolbar_button_empty"
        )
    }

    func testDiffViewerToolbarButtonWithStats() {
        assertMacSnapshot(
            DiffViewerToolbarButton(diffStats: DiffStats(additions: 120, deletions: 45), action: {})
                .padding(12),
            size: CGSize(width: 180, height: 56),
            named: "diff_viewer_toolbar_button_stats"
        )
    }

    func testDiffViewerPaneHeaderOpenPRAction() {
        assertMacSnapshot(
            DiffViewerPaneHeader(
                activeDirectory: "/tmp/alveary",
                contextualAction: .openPR,
                selectedFile: nil,
                areAgentActionsEnabled: true,
                onRefresh: {},
                onCommitRequested: {},
                onOpenPRRequested: {},
                onViewPRRequested: { _ in },
                onStageSelectedFile: {},
                onUnstageSelectedFile: {},
                onDiscardSelectedFile: {}
            ),
            size: CGSize(width: 460, height: 92),
            named: "diff_viewer_header_open_pr"
        )
    }

    func testDiffViewerPanePopulated() async {
        let fixture = SnapshotDiffViewerFixture(
            gitService: SnapshotMockGitService(
                statusResults: [[
                    FileStatus(path: "Alveary/Views/Input/ChatInputField.swift", originalPath: nil, status: .modified, isStaged: false),
                    FileStatus(path: "Alveary/Views/Chat/ChatView.swift", originalPath: nil, status: .added, isStaged: true)
                ]],
                diffResults: [Self.modifiedDiff(path: "Alveary/Views/Input/ChatInputField.swift")]
            )
        )
        defer { fixture.viewModel.tearDown() }

        let selectedFile = FileStatus(
            path: "Alveary/Views/Input/ChatInputField.swift",
            originalPath: nil,
            status: .modified,
            isStaged: false
        )

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
                onCommitRequested: {},
                onOpenPRRequested: {}
            ),
            size: CGSize(width: 460, height: 720),
            named: "diff_viewer_populated"
        )
    }

    func testDiffViewerPanePopulatedNarrow() async {
        let fixture = SnapshotDiffViewerFixture(
            gitService: SnapshotMockGitService(
                statusResults: [[
                    FileStatus(path: "Alveary/Views/Input/ChatInputField.swift", originalPath: nil, status: .modified, isStaged: false),
                    FileStatus(path: "Alveary/Views/Chat/ChatView.swift", originalPath: nil, status: .added, isStaged: true)
                ]],
                diffResults: [Self.modifiedDiff(path: "Alveary/Views/Input/ChatInputField.swift")]
            )
        )
        defer { fixture.viewModel.tearDown() }

        let selectedFile = FileStatus(
            path: "Alveary/Views/Input/ChatInputField.swift",
            originalPath: nil,
            status: .modified,
            isStaged: false
        )

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
                onCommitRequested: {},
                onOpenPRRequested: {}
            ),
            size: CGSize(width: 360, height: 720),
            named: "diff_viewer_populated_narrow"
        )
    }

    func testDiffViewerPaneRawFallback() async {
        let path = "AlvearyTests/Services/ShellRunnerTests.swift"
        let fixture = SnapshotDiffViewerFixture(
            gitService: SnapshotMockGitService(
                statusResults: [[
                    FileStatus(path: path, originalPath: nil, status: .modified, isStaged: false)
                ]],
                diffResults: [Self.rawFallbackDiff(path: path)]
            )
        )
        defer { fixture.viewModel.tearDown() }

        let selectedFile = FileStatus(
            path: path,
            originalPath: nil,
            status: .modified,
            isStaged: false
        )

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
                onCommitRequested: {},
                onOpenPRRequested: {}
            ),
            size: CGSize(width: 460, height: 720),
            named: "diff_viewer_raw_fallback"
        )
    }

    func testDiffViewerFileListSectionLoading() {
        assertMacSnapshot(
            DiffViewerFileListSection(
                files: [],
                isGitRepository: true,
                isLoading: true,
                isSelected: { _ in false },
                fileDisplayName: { $0.path },
                statusSymbol: { _ in "●" },
                onSelectFile: { _ in },
                onStageFile: { _ in },
                onUnstageFile: { _ in },
                onDiscardFile: { _ in }
            ),
            size: CGSize(width: 420, height: 240),
            named: "diff_viewer_file_list_loading"
        )
    }

    func testDiffViewerPaneRenamedMetadata() async {
        let oldPath = "Alveary/Views/Input/ChatInputField.swift"
        let newPath = "Alveary/Views/Input/ComposerInputField.swift"
        let fixture = SnapshotDiffViewerFixture(
            gitService: SnapshotMockGitService(
                statusResults: [[
                    FileStatus(path: newPath, originalPath: oldPath, status: .renamed, isStaged: false)
                ]],
                diffResults: [Self.renamedDiff(oldPath: oldPath, newPath: newPath)]
            )
        )
        defer { fixture.viewModel.tearDown() }

        let selectedFile = FileStatus(
            path: newPath,
            originalPath: oldPath,
            status: .renamed,
            isStaged: false
        )

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
                onCommitRequested: {},
                onOpenPRRequested: {}
            ),
            size: CGSize(width: 460, height: 720),
            named: "diff_viewer_renamed_metadata"
        )
    }
}
