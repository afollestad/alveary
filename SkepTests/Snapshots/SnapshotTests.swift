import XCTest

@testable import Skep

@MainActor
final class SnapshotTests: XCTestCase {
    func testEmptyThreadStateHero() {
        assertMacSnapshot(
            EmptyThreadState(
                showsRetryState: false,
                setupPhase: nil,
                error: nil,
                onRetry: {}
            ),
            size: CGSize(width: 900, height: 560),
            named: "empty_thread_hero"
        )
    }

    func testEmptyThreadStateRetry() {
        assertMacSnapshot(
            EmptyThreadState(
                showsRetryState: true,
                setupPhase: nil,
                error: "Claude could not start because the working directory could not be prepared.",
                onRetry: {}
            ),
            size: CGSize(width: 900, height: 560),
            named: "empty_thread_retry"
        )
    }

    func testChatInputFieldIdle() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant("Investigate the flaky login flow and summarize what changed."),
                mode: .idle,
                onSubmit: {},
                onSteer: {},
                onStop: nil,
                selectedModel: .constant("default"),
                selectedEffort: .constant("medium"),
                selectedPermissionMode: .constant("default"),
                supportedPermissionModes: samplePermissionModes,
                supportedEffortLevels: ["low", "medium", "high"],
                supportsMidTurnSteering: true,
                workingDirectory: "/tmp/skep",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 760, height: 240),
            named: "chat_input_idle"
        )
    }

    func testChatInputFieldBusySteering() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant("Focus on the failing Settings screen snapshots next."),
                mode: .busy(canStop: true),
                onSubmit: {},
                onSteer: {},
                onStop: {},
                selectedModel: .constant("sonnet"),
                selectedEffort: .constant("high"),
                selectedPermissionMode: .constant("acceptEdits"),
                supportedPermissionModes: samplePermissionModes,
                supportedEffortLevels: ["low", "medium", "high"],
                supportsMidTurnSteering: true,
                workingDirectory: "/tmp/skep",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 760, height: 240),
            named: "chat_input_busy_steering"
        )
    }

    func testChatInputFieldProgressOnly() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant("Review the updated MCP cards once the session comes back."),
                mode: .progressOnly(.initialSetup),
                onSubmit: {},
                onSteer: {},
                onStop: nil,
                selectedModel: .constant("default"),
                selectedEffort: .constant("medium"),
                selectedPermissionMode: .constant("default"),
                supportedPermissionModes: samplePermissionModes,
                supportedEffortLevels: ["low", "medium", "high"],
                supportsMidTurnSteering: false,
                workingDirectory: "/tmp/skep",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 760, height: 240),
            named: "chat_input_progress_only"
        )
    }

    func testChatInputFieldBusyQueueOnly() {
        assertMacSnapshot(
            ChatInputField(
                text: .constant("Queue the follow-up diff audit after the current turn finishes."),
                mode: .busy(canStop: false),
                onSubmit: {},
                onSteer: {},
                onStop: nil,
                selectedModel: .constant("default"),
                selectedEffort: .constant("medium"),
                selectedPermissionMode: .constant("default"),
                supportedPermissionModes: samplePermissionModes,
                supportedEffortLevels: ["low", "medium", "high"],
                supportsMidTurnSteering: true,
                workingDirectory: "/tmp/skep",
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            ),
            size: CGSize(width: 760, height: 240),
            named: "chat_input_busy_queue_only"
        )
    }

    func testComposerAutocompletePopupFiles() {
        assertMacSnapshot(
            ComposerAutocompletePopup(
                autocomplete: sampleFileAutocomplete,
                onSelect: { _ in }
            ),
            size: CGSize(width: 540, height: 280),
            named: "composer_autocomplete_files"
        )
    }

    func testComposerAutocompletePopupSkills() {
        assertMacSnapshot(
            ComposerAutocompletePopup(
                autocomplete: sampleSkillAutocomplete,
                onSelect: { _ in }
            ),
            size: CGSize(width: 540, height: 280),
            named: "composer_autocomplete_skills"
        )
    }

    func testQueuedMessageBubbleWithContextAndRetry() {
        assertMacSnapshot(
            QueuedMessageBubble(
                text: "After the current turn, also validate the diff refresh logic against renamed files.",
                showsStagedContext: true,
                showsRetry: true,
                isDismissDisabled: false,
                onRetry: {},
                onDismiss: {}
            ),
            size: CGSize(width: 760, height: 220),
            named: "queued_message_with_context"
        )
    }

    func testWorkingBlockCollapsed() {
        assertMacSnapshot(
            WorkingBlock(tools: sampleTools),
            size: CGSize(width: 760, height: 180),
            named: "working_block_collapsed"
        )
    }

    func testSubAgentBlockMixedStates() {
        assertMacSnapshot(
            SubAgentBlock(agents: sampleSubAgents),
            size: CGSize(width: 760, height: 220),
            named: "subagent_block_mixed"
        )
    }

    func testTaskListBlockMixedStates() {
        assertMacSnapshot(
            TaskListBlock(tasks: sampleTasks),
            size: CGSize(width: 760, height: 240),
            named: "task_list_mixed"
        )
    }

    func testPromptBlockUnanswered() {
        assertMacSnapshot(
            PromptBlock(prompt: samplePrompt, isBusy: false) { _ in nil },
            size: CGSize(width: 760, height: 420),
            named: "prompt_block_unanswered"
        )
    }

    func testPromptBlockAnswered() {
        assertMacSnapshot(
            PromptBlock(prompt: answeredPrompt, isBusy: false) { _ in nil },
            size: CGSize(width: 760, height: 220),
            named: "prompt_block_answered"
        )
    }

    func testSkillsScreenPopulated() async {
        let viewModel = SkillsViewModel(skillsService: SnapshotSkillsService())
        await viewModel.load()

        assertMacSnapshot(
            SkillsScreen(viewModel: viewModel),
            size: CGSize(width: 1120, height: 900),
            named: "skills_screen_populated"
        )
    }

    func testMCPScreenPopulated() async {
        let viewModel = MCPViewModel(mcpService: SnapshotMCPService())
        await viewModel.load()

        assertMacSnapshot(
            MCPScreen(viewModel: viewModel),
            size: CGSize(width: 1120, height: 900),
            named: "mcp_screen_populated"
        )
    }

    func testSettingsScreenGeneralTab() {
        var settings = AppSettings()
        settings.permissionMode = "acceptEdits"
        settings.effort = "high"
        settings.autoTrustWorktrees = false
        settings.theme = "light"
        settings.codeFontFamily = "JetBrains Mono"
        settings.notifications.soundName = "Pop"

        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(current: settings))

        assertMacSnapshot(
            SettingsScreen(viewModel: viewModel, onClose: {}),
            size: CGSize(width: 1100, height: 820),
            named: "settings_screen_general"
        )
    }

    func testSettingsScreenRepositoryTab() {
        var settings = AppSettings()
        settings.branchPrefix = "af"

        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService(current: settings))

        assertMacSnapshot(
            SettingsScreen(
                viewModel: viewModel,
                onClose: {},
                initialTabRawValue: "repository"
            ),
            size: CGSize(width: 1100, height: 820),
            named: "settings_screen_repository"
        )
    }

    func testSidebarViewPopulated() async throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/skep", name: "Skep")
        let activeThread = AgentThread(name: "Refactor Chat Input", project: project)
        let archivedThread = AgentThread(name: "Audit Diff Watcher", archivedAt: Date(timeIntervalSince1970: 1_713_000_000), project: project)
        let activeConversation = Conversation(id: "main", title: "Main", provider: "claude", thread: activeThread)
        let archivedConversation = Conversation(id: "archive", title: "Main", provider: "claude", thread: archivedThread)
        activeThread.conversations = [activeConversation]
        archivedThread.conversations = [archivedConversation]
        project.threads = [activeThread, archivedThread]

        let secondaryProject = Project(path: "/tmp/tools", name: "Tools")

        fixture.context.insert(project)
        fixture.context.insert(activeThread)
        fixture.context.insert(archivedThread)
        fixture.context.insert(activeConversation)
        fixture.context.insert(archivedConversation)
        fixture.context.insert(secondaryProject)
        try fixture.context.save()
        await fixture.agentsManager.setStatus(.busy, for: activeConversation.id)

        let appState = AppState()
        appState.selectedSidebarItem = .thread(activeThread)

        assertMacSnapshot(
            SidebarView(viewModel: fixture.viewModel, appState: appState)
                .modelContainer(fixture.container),
            size: CGSize(width: 320, height: 720),
            named: "sidebar_populated"
        )
    }

    func testDiffViewerPanePopulated() async {
        let fixture = SnapshotDiffViewerFixture(
            gitService: SnapshotMockGitService(
                statusResults: [[
                    FileStatus(path: "Skep/Views/Input/ChatInputField.swift", originalPath: nil, status: .modified, isStaged: false),
                    FileStatus(path: "Skep/Views/Chat/ChatView.swift", originalPath: nil, status: .added, isStaged: true)
                ]],
                diffResults: [Self.modifiedDiff(path: "Skep/Views/Input/ChatInputField.swift")]
            )
        )
        defer { fixture.viewModel.tearDown() }

        let selectedFile = FileStatus(
            path: "Skep/Views/Input/ChatInputField.swift",
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
                    FileStatus(path: "Skep/Views/Input/ChatInputField.swift", originalPath: nil, status: .modified, isStaged: false),
                    FileStatus(path: "Skep/Views/Chat/ChatView.swift", originalPath: nil, status: .added, isStaged: true)
                ]],
                diffResults: [Self.modifiedDiff(path: "Skep/Views/Input/ChatInputField.swift")]
            )
        )
        defer { fixture.viewModel.tearDown() }

        let selectedFile = FileStatus(
            path: "Skep/Views/Input/ChatInputField.swift",
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
        let path = "SkepTests/Services/ShellRunnerTests.swift"
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

    func testDiffViewerPaneRenamedMetadata() async {
        let oldPath = "Skep/Views/Input/ChatInputField.swift"
        let newPath = "Skep/Views/Input/ComposerInputField.swift"
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
    static func modifiedDiff(path: String) -> String {
        let leadingContext = (1...5).map { "    private let leadingContext\($0) = \($0)" }
        let middleContext = (6...20).map { "        let intermediateContext\($0) = \($0)" }
        let trailingContext = (21...24).map { "    private let trailingContext\($0) = \($0)" }

        var lines = [
            "diff --git a/\(path) b/\(path)",
            "--- a/\(path)",
            "+++ b/\(path)",
            "@@ -10,34 +10,36 @@ struct ChatInputField: View {",
            " struct ChatInputField: View {"
        ]
        lines.append(contentsOf: leadingContext.map { " \($0)" })
        lines.append(contentsOf: [
            "-    private let maxAutocompleteResults = 40",
            "+    private let maxAutocompleteResults = 50",
            "+    private let autocompleteDebounceNanoseconds: UInt64 = 75_000_000",
            "+    private let diffPreviewFont = Font.system(.caption, design: .monospaced)"
        ])
        lines.append(contentsOf: middleContext.map { " \($0)" })
        lines.append(contentsOf: [
            "-        Button(\"Send\", action: onSubmit)",
            "+        Button(\"Send\", action: onSubmit)",
            "+            .keyboardShortcut(.return, modifiers: [.command])"
        ])
        lines.append(contentsOf: trailingContext.map { " \($0)" })
        lines.append(" }")
        return lines.joined(separator: "\n")
    }

    static func renamedDiff(oldPath: String, newPath: String) -> String {
        """
        diff --git a/\(oldPath) b/\(newPath)
        similarity index 100%
        rename from \(oldPath)
        rename to \(newPath)
        """
    }

    static func rawFallbackDiff(path: String) -> String {
        let longLine = String(repeating: "stream-json-output-segment-", count: 12)

        return """
        diff --git a/\(path) b/\(path)
        --- a/\(path)
        +++ b/\(path)
        +\(longLine)
        +func testCancellationWhileStreamingOutputDoesNotCrash() async throws {
        +    let runner = DefaultShellRunner()
        +    let task = Task {
        +        try await runner.run(executable: "/usr/bin/perl", args: ["-e", "...streaming output..."])
        +    }
        """
    }
}
