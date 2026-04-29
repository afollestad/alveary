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

    func testDiffViewerPaneHeaderOpenPRAction() {
        assertMacSnapshot(
            DiffViewerPaneHeader(
                activeDirectory: "/tmp/alveary",
                contextualAction: .openPR,
                selectedFiles: [],
                areAgentActionsEnabled: true,
                isRefreshing: false,
                showsFileListDivider: false,
                onRefresh: {},
                onCommitRequested: {},
                onOpenPRRequested: {},
                onViewPRRequested: { _ in },
                onStageSelectedFiles: {},
                onUnstageSelectedFiles: {},
                onDiscardSelectedFiles: {}
            ),
            size: CGSize(width: 460, height: 92),
            named: "diff_viewer_header_open_pr"
        )
    }

    func testDiffViewerPaneHeaderMixedSelectionActions() {
        assertMacSnapshot(
            DiffViewerPaneHeader(
                activeDirectory: "/tmp/alveary",
                contextualAction: .commit,
                selectedFiles: [
                    FileStatus(path: "Sources/App.swift", originalPath: nil, status: .modified, isStaged: false),
                    FileStatus(path: "Tests/AppTests.swift", originalPath: nil, status: .modified, isStaged: true)
                ],
                areAgentActionsEnabled: true,
                isRefreshing: false,
                showsFileListDivider: false,
                onRefresh: {},
                onCommitRequested: {},
                onOpenPRRequested: {},
                onViewPRRequested: { _ in },
                onStageSelectedFiles: {},
                onUnstageSelectedFiles: {},
                onDiscardSelectedFiles: {}
            ),
            size: CGSize(width: 520, height: 92),
            named: "diff_viewer_header_mixed_selection"
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

    func testDiffViewerPaneMultiSelectionPreviewState() async {
        let firstFile = FileStatus(path: "Alveary/Views/Input/ChatInputField.swift", originalPath: nil, status: .modified, isStaged: false)
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
                areAgentActionsEnabled: true,
                onCommitRequested: {},
                onOpenPRRequested: {}
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
                selectedFiles: [],
                isGitRepository: true,
                isLoading: true,
                isSelected: { _ in false },
                fileDisplayName: { $0.path },
                statusSymbol: { _ in "●" },
                onSelectFile: { _, _ in },
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
                statusSymbol: { file in file.isStaged ? "+" : "●" },
                onSelectFile: { _, _ in },
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

private extension SnapshotTests {
    func primaryToolbarButtonGroup(
        selectedThread: AgentThread? = nil,
        projectActions: [AlvearyProjectConfig.ProjectAction] = [],
        terminalDisplayState: TerminalToolbarDisplayState = .idle,
        diffDisplayState: DiffViewerToolbarDisplayState
    ) -> some View {
        PrimaryToolbarButtonGroup(
            selectedThread: selectedThread,
            projectActions: projectActions,
            terminalTitle: "Show Terminal",
            terminalDisplayState: terminalDisplayState,
            terminalHelpText: "Show Terminal (\(KeyboardShortcut.toggleTerminalPane.displayString))",
            diffDisplayState: diffDisplayState,
            diffHelpText: "Show Diff Viewer (\(KeyboardShortcut.toggleDiffViewer.displayString))",
            diffAccessibilityLabel: "Show Diff Viewer",
            diffAccessibilityValue: "",
            onProjectAction: { _, _ in },
            onToggleTerminal: {},
            onToggleDiffViewer: {},
            onOpenSettings: {}
        )
    }
}
