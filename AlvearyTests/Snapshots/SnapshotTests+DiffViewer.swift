import XCTest
import SwiftUI

@testable import Alveary

extension SnapshotTests {
    func testDiffViewerToolbarButtonEmptyStats() {
        assertMacSnapshot(
            DiffViewerToolbarButton(displayState: .idle(.empty), action: {})
                .padding(12),
            size: CGSize(width: 120, height: 56),
            named: "diff_viewer_toolbar_button_empty"
        )
    }

    func testDiffViewerToolbarButtonWithStats() {
        assertMacSnapshot(
            DiffViewerToolbarButton(displayState: .idle(DiffStats(additions: 120, deletions: 45)), action: {})
                .padding(12),
            size: CGSize(width: 180, height: 56),
            named: "diff_viewer_toolbar_button_stats"
        )
    }

    func testDiffViewerToolbarButtonLoading() {
        assertMacSnapshot(
            DiffViewerToolbarButton(displayState: .loading, action: {})
                .padding(12),
            size: CGSize(width: 120, height: 56),
            named: "diff_viewer_toolbar_button_loading"
        )
    }

    func testPrimaryToolbarButtonGroupEmptyDiff() {
        assertMacSnapshot(
            primaryToolbarButtonGroup(diffDisplayState: .idle(.empty))
                .padding(8),
            size: CGSize(width: 180, height: 64),
            named: "primary_toolbar_button_group_empty_diff"
        )
    }

    func testPrimaryToolbarButtonGroupLoadingDiff() {
        assertMacSnapshot(
            primaryToolbarButtonGroup(
                terminalDisplayState: .running,
                diffDisplayState: .loading
            )
            .padding(8),
            size: CGSize(width: 220, height: 64),
            named: "primary_toolbar_button_group_loading_diff"
        )
    }

    func testPrimaryToolbarButtonGroupPopulatedDiff() {
        assertMacSnapshot(
            primaryToolbarButtonGroup(diffDisplayState: .idle(DiffStats(additions: 120, deletions: 45)))
                .padding(8),
            size: CGSize(width: 260, height: 64),
            named: "primary_toolbar_button_group_populated_diff"
        )
    }

    func testPrimaryToolbarButtonGroupProjectAction() {
        let thread = AgentThread(name: "Toolbar Action")

        assertMacSnapshot(
            primaryToolbarButtonGroup(
                selectedThread: thread,
                projectActions: [
                    AlvearyProjectConfig.ProjectAction(
                        icon: "hammer",
                        name: "Build",
                        command: "swift build"
                    )
                ],
                diffDisplayState: .idle(DiffStats(additions: 120, deletions: 45))
            )
            .padding(8),
            size: CGSize(width: 320, height: 64),
            named: "primary_toolbar_button_group_project_action"
        )
    }

    func testPrimaryToolbarButtonGroupProjectActionEmptyDiff() {
        let thread = AgentThread(name: "Toolbar Action")

        assertMacSnapshot(
            primaryToolbarButtonGroup(
                selectedThread: thread,
                projectActions: [
                    AlvearyProjectConfig.ProjectAction(
                        icon: "hammer",
                        name: "Build",
                        command: "swift build"
                    )
                ],
                diffDisplayState: .idle(.empty)
            )
            .padding(8),
            size: CGSize(width: 240, height: 64),
            named: "primary_toolbar_button_group_project_action_empty_diff"
        )
    }

    func testPrimaryToolbarButtonGroupProjectActionLoadingDiff() {
        let thread = AgentThread(name: "Toolbar Action")

        assertMacSnapshot(
            primaryToolbarButtonGroup(
                selectedThread: thread,
                projectActions: [
                    AlvearyProjectConfig.ProjectAction(
                        icon: "hammer",
                        name: "Build",
                        command: "swift build"
                    )
                ],
                terminalDisplayState: .running,
                diffDisplayState: .loading
            )
            .padding(8),
            size: CGSize(width: 260, height: 64),
            named: "primary_toolbar_button_group_project_action_loading_diff"
        )
    }

    func testPrimaryToolbarButtonGroupMultipleProjectActions() {
        let thread = AgentThread(name: "Toolbar Actions")

        assertMacSnapshot(
            primaryToolbarButtonGroup(
                selectedThread: thread,
                projectActions: [
                    AlvearyProjectConfig.ProjectAction(
                        icon: "hammer",
                        name: "Build",
                        command: "swift build"
                    ),
                    AlvearyProjectConfig.ProjectAction(
                        icon: "checkmark.circle",
                        name: "Test",
                        command: "swift test"
                    )
                ],
                diffDisplayState: .idle(DiffStats(additions: 120, deletions: 45))
            )
            .padding(8),
            size: CGSize(width: 360, height: 64),
            named: "primary_toolbar_button_group_multiple_project_actions"
        )
    }

    func testDiffViewerPaneHeaderMixedSelectionActions() {
        assertMacSnapshot(
            DiffViewerPaneHeader(
                activeDirectory: "/tmp/alveary",
                mode: .currentChanges,
                contextualAction: .commit,
                selectedFiles: [
                    FileStatus(path: "Sources/App.swift", originalPath: nil, status: .modified, isStaged: false),
                    FileStatus(path: "Tests/AppTests.swift", originalPath: nil, status: .modified, isStaged: true)
                ],
                canCommit: true,
                showsFileListDivider: false,
                showsFileActions: true,
                onModeSelected: { _ in },
                onCommitRequested: {},
                onStageSelectedFiles: {},
                onUnstageSelectedFiles: {},
                onDiscardSelectedFiles: {}
            ),
            size: CGSize(width: 520, height: 72),
            named: "diff_viewer_header_mixed_selection"
        )
    }

    func testDiffViewerPanePopulated() async {
        let fixture = SnapshotDiffViewerFixture(
            gitService: SnapshotMockGitService(
                statusResults: [[
                    FileStatus(path: "Alveary/Views/Chat/ChatView.swift", originalPath: nil, status: .modified, isStaged: false),
                    FileStatus(path: "Alveary/Views/Chat/ChatView.swift", originalPath: nil, status: .added, isStaged: true)
                ]],
                diffResults: [Self.modifiedDiff(path: "Alveary/Views/Chat/ChatView.swift")]
            )
        )
        defer { fixture.viewModel.tearDown() }

        let selectedFile = FileStatus(
            path: "Alveary/Views/Chat/ChatView.swift",
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
                canCommit: true,
                onCommitRequested: {},
            ),
            size: CGSize(width: 460, height: 720),
            named: "diff_viewer_populated"
        )
    }

    func testDiffViewerPanePopulatedNarrow() async {
        let fixture = SnapshotDiffViewerFixture(
            gitService: SnapshotMockGitService(
                statusResults: [[
                    FileStatus(path: "Alveary/Views/Chat/ChatView.swift", originalPath: nil, status: .modified, isStaged: false),
                    FileStatus(path: "Alveary/Views/Chat/ChatView.swift", originalPath: nil, status: .added, isStaged: true)
                ]],
                diffResults: [Self.modifiedDiff(path: "Alveary/Views/Chat/ChatView.swift")]
            )
        )
        defer { fixture.viewModel.tearDown() }

        let selectedFile = FileStatus(
            path: "Alveary/Views/Chat/ChatView.swift",
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
                canCommit: true,
                onCommitRequested: {},
            ),
            size: CGSize(width: 360, height: 720),
            named: "diff_viewer_populated_narrow"
        )
    }

    func testDiffViewerPaneUntrackedFileCompactGutter() async {
        let path = "onyx-page-5891.txt"
        let selectedFile = FileStatus(path: path, originalPath: nil, status: .untracked, isStaged: false)
        let fixture = SnapshotDiffViewerFixture(
            gitService: SnapshotMockGitService(
                statusResults: [[selectedFile]],
                diffResults: [],
                syntheticDiffResults: [Self.newFileDiff(path: path)]
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
                onCommitRequested: {},
            ),
            size: CGSize(width: 460, height: 520),
            named: "diff_viewer_untracked_compact_gutter"
        )
    }

    func testDiffViewerPaneMultiSelectionPreviewState() async {
        let firstFile = FileStatus(path: "Alveary/Views/Chat/ChatView.swift", originalPath: nil, status: .modified, isStaged: false)
        let secondFile = FileStatus(path: "Alveary/Views/Chat/ChatView.swift", originalPath: nil, status: .added, isStaged: true)
        let fixture = SnapshotDiffViewerFixture(
            gitService: SnapshotMockGitService(
                statusResults: [[firstFile, secondFile]],
                diffResults: [
                    Self.modifiedDiff(path: firstFile.path),
                    Self.modifiedDiff(path: secondFile.path)
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
        await fixture.viewModel.selectFile(firstFile, in: fixture.directory)
        await fixture.viewModel.selectFile(secondFile, in: fixture.directory, behavior: .toggle)

        assertMacSnapshot(
            DiffViewerPane(
                viewModel: fixture.viewModel,
                canCommit: true,
                onCommitRequested: {},
            ),
            size: CGSize(width: 460, height: 720),
            named: "diff_viewer_multi_selection_preview"
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
                canCommit: true,
                onCommitRequested: {},
            ),
            size: CGSize(width: 460, height: 720),
            named: "diff_viewer_raw_fallback"
        )
    }

    func testDiffViewerFileListSectionLoading() {
        assertMacSnapshot(
            DiffViewerFileListSection(
                files: [],
                selectedFiles: [],
                isGitRepository: true,
                isLoading: true,
                isSelected: { _ in false },
                fileDisplayName: { $0.path },
                onSelectFile: { _, _ in },
                onSelectAllFiles: {},
                onNavigateFile: { _, _ in nil },
                onStageFiles: { _ in },
                onUnstageFiles: { _ in },
                onDiscardFiles: { _ in },
                isTopDividerVisible: .constant(false)
            ),
            size: CGSize(width: 420, height: 240),
            named: "diff_viewer_file_list_loading"
        )
    }

    func testDiffViewerFileListSectionMultipleSelection() {
        let files = [
            FileStatus(path: "Sources/App.swift", originalPath: nil, status: .modified, isStaged: false),
            FileStatus(path: "Sources/Composer.swift", originalPath: nil, status: .added, isStaged: false),
            FileStatus(path: "Tests/AppTests.swift", originalPath: nil, status: .modified, isStaged: true)
        ]
        let selectedFiles = [files[0], files[2]]

        assertMacSnapshot(
            DiffViewerFileListSection(
                files: files,
                selectedFiles: selectedFiles,
                isGitRepository: true,
                isLoading: false,
                isSelected: { selectedFiles.contains($0) },
                fileDisplayName: { $0.path },
                onSelectFile: { _, _ in },
                onSelectAllFiles: {},
                onNavigateFile: { _, _ in nil },
                onStageFiles: { _ in },
                onUnstageFiles: { _ in },
                onDiscardFiles: { _ in },
                isTopDividerVisible: .constant(false)
            ),
            size: CGSize(width: 420, height: 240),
            named: "diff_viewer_file_list_multiple_selection"
        )
    }

    func testDiffViewerPaneRenamedMetadata() async {
        let oldPath = "Alveary/Views/Chat/ChatView.swift"
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
                canCommit: true,
                onCommitRequested: {},
            ),
            size: CGSize(width: 460, height: 720),
            named: "diff_viewer_renamed_metadata"
        )
    }
}
