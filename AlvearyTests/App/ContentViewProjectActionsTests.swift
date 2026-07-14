import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ContentViewProjectActionsTests: XCTestCase {
    func testContentViewUsesModelContainerMainContextForViewModels() {
        let component = AppDI.makeTestComponent(isStoredInMemoryOnly: true)

        let dependencies = ContentViewDependencies.resolve(component)
        XCTAssertTrue(dependencies.modelContainer.mainContext === component.modelContainer.mainContext)
    }

    func testDiffToolbarStateUsesWorkingTreeStatsWhenPaneModeIsCommits() {
        let stats = DiffStats(additions: 9, deletions: 3)

        let displayState = ContentView.diffViewerToolbarDisplayState(
            stats: stats,
            isLoading: false,
            paneMode: .commits
        )

        XCTAssertEqual(displayState, .idle(stats))
    }

    func testSidebarSelectionDiffActionCapabilitiesAllowCommitForProjectsAndThreads() {
        let project = Project(path: "/tmp/project", name: "Alveary")
        let thread = AgentThread(name: "Thread", project: project)

        XCTAssertTrue(SidebarItem.project(project).canCommitDiffChanges)
        XCTAssertTrue(SidebarItem.thread(thread).canCommitDiffChanges)
        XCTAssertFalse(SidebarItem.skills.canCommitDiffChanges)
        XCTAssertFalse(SidebarItem.scheduled.canCommitDiffChanges)
    }

    func testDiffCommitTargetResolverResolvesThreadTarget() throws {
        let fixture = try makeDiffCommitTargetFixture(worktreePath: "/tmp/worktree")
        fixture.appState.selectedSidebarItem = .thread(fixture.thread)
        fixture.appState.selectedConversationIDs[fixture.thread.persistentModelID] = fixture.conversation.persistentModelID

        let snapshot = DiffGitCommitTargetSnapshotResolver.resolve(
            selection: fixture.appState.selectedSidebarItem,
            modelContext: fixture.context,
            appState: fixture.appState,
            activeDirectory: "/tmp/worktree"
        )

        XCTAssertEqual(snapshot?.directory, "/tmp/worktree")
        XCTAssertEqual(snapshot?.targetName, "Toolbar Action")
        XCTAssertEqual(snapshot?.baseBranch, "develop")
        XCTAssertEqual(snapshot?.remoteName, "upstream")
        XCTAssertEqual(snapshot?.generationRoute, .thread)
    }

    func testDiffCommitTargetResolverResolvesProjectTargetWithNameFallback() throws {
        let fixture = try makeDiffCommitTargetFixture(projectPath: "/tmp/FallbackProject", projectName: "   ")
        fixture.appState.selectedSidebarItem = .project(fixture.project)

        let snapshot = DiffGitCommitTargetSnapshotResolver.resolve(
            selection: fixture.appState.selectedSidebarItem,
            modelContext: fixture.context,
            appState: fixture.appState,
            activeDirectory: "/tmp/FallbackProject"
        )

        XCTAssertEqual(snapshot?.directory, "/tmp/FallbackProject")
        XCTAssertEqual(snapshot?.targetName, "FallbackProject")
        XCTAssertEqual(snapshot?.baseBranch, "develop")
        XCTAssertEqual(snapshot?.remoteName, "upstream")
        XCTAssertEqual(snapshot?.generationRoute, .project(directory: "/tmp/FallbackProject"))
    }

    func testDiffCommitTargetResolverReturnsNilWithoutSelectionOrActiveDirectory() throws {
        let fixture = try makeDiffCommitTargetFixture()

        XCTAssertNil(DiffGitCommitTargetSnapshotResolver.resolve(
            selection: nil,
            modelContext: fixture.context,
            appState: fixture.appState,
            activeDirectory: "/tmp/project"
        ))
        XCTAssertNil(DiffGitCommitTargetSnapshotResolver.resolve(
            selection: .project(fixture.project),
            modelContext: fixture.context,
            appState: fixture.appState,
            activeDirectory: nil
        ))
    }

    func testDiffCommitTargetResolverRejectsScheduledDestination() throws {
        let fixture = try makeDiffCommitTargetFixture()

        XCTAssertNil(DiffGitCommitTargetSnapshotResolver.resolve(
            selection: .scheduled,
            modelContext: fixture.context,
            appState: fixture.appState,
            activeDirectory: fixture.project.path
        ))
    }

    func testDiffCommitTargetResolverRejectsStaleActiveDirectory() throws {
        let fixture = try makeDiffCommitTargetFixture()

        XCTAssertNil(DiffGitCommitTargetSnapshotResolver.resolve(
            selection: .project(fixture.project),
            modelContext: fixture.context,
            appState: fixture.appState,
            activeDirectory: "/tmp/other-project"
        ))
    }

    func testDiffCommitTargetResolverReturnsNilForThreadWithoutDirectory() throws {
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let appState = AppState()
        let conversation = Conversation(title: "Main", provider: "claude")
        let thread = AgentThread(name: "No Project", conversations: [conversation])
        context.insert(thread)
        try context.save()
        appState.selectedConversationIDs[thread.persistentModelID] = conversation.persistentModelID

        XCTAssertNil(DiffGitCommitTargetSnapshotResolver.resolve(
            selection: .thread(thread),
            modelContext: context,
            appState: appState,
            activeDirectory: "/tmp/project"
        ))
    }

    func testProjectActionExecutionContextPrefersWorktreePathAndCarriesThreadMetadata() throws {
        let project = Project(path: "/tmp/project", name: "Alveary")
        let thread = AgentThread(name: "Toolbar Action", worktreePath: "/tmp/worktree", project: project)
        let action = AlvearyProjectConfig.ProjectAction(icon: "hammer", name: "Build", command: "./scripts/build.sh")

        let context = try XCTUnwrap(ProjectActionExecutionContext(thread: thread, action: action))

        XCTAssertEqual(context.title, "Build")
        XCTAssertEqual(context.threadID, thread.persistentModelID)
        XCTAssertEqual(context.threadName, "Toolbar Action")
        XCTAssertEqual(context.currentDirectory, "/tmp/worktree")
        XCTAssertEqual(context.command, "./scripts/build.sh")
    }

    func testProjectActionExecutionContextFallsBackToProjectPath() {
        let project = Project(path: "/tmp/project", name: "Alveary")
        let thread = AgentThread(name: "Toolbar Action", project: project)
        let action = AlvearyProjectConfig.ProjectAction(name: "Test", command: "./scripts/test.sh")

        let context = ProjectActionExecutionContext(thread: thread, action: action)

        XCTAssertEqual(context?.currentDirectory, "/tmp/project")
    }

    func testProjectActionExecutionContextReturnsNilWithoutRunnableDirectory() {
        let thread = AgentThread(name: "Toolbar Action")
        let action = AlvearyProjectConfig.ProjectAction(name: "Test", command: "./scripts/test.sh")

        XCTAssertNil(ProjectActionExecutionContext(thread: thread, action: action))
    }

    func testResolvedLastOpenThreadSelectionReturnsMatchingThreadAndConversation() throws {
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let project = Project(path: "/tmp/project", name: "Alveary")
        let conversation = Conversation(title: "Main", provider: "claude")
        let thread = AgentThread(name: "Toolbar Action", project: project, conversations: [conversation])
        project.threads.append(thread)
        context.insert(project)
        try context.save()

        var settings = AppSettings()
        settings.reopenLastThreadAndConversationOnLaunch = true
        settings.lastOpenThreadID = thread.persistentModelID
        settings.lastOpenConversationID = conversation.persistentModelID

        let selection = resolvedLastOpenThreadSelection(settings: settings, modelContext: context)

        XCTAssertEqual(selection?.thread.persistentModelID, thread.persistentModelID)
        XCTAssertEqual(selection?.conversationID, conversation.persistentModelID)
    }

    func testResolvedLastOpenThreadSelectionIgnoresDraftThread() throws {
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let project = Project(path: "/tmp/draft-restore", name: "Draft")
        let conversation = Conversation(title: "Main", provider: "claude")
        let thread = AgentThread(name: "Draft", isDraft: true, project: project, conversations: [conversation])
        project.threads.append(thread)
        context.insert(project)
        try context.save()

        var settings = AppSettings()
        settings.reopenLastThreadAndConversationOnLaunch = true
        settings.lastOpenThreadID = thread.persistentModelID
        settings.lastOpenConversationID = conversation.persistentModelID

        XCTAssertNil(resolvedLastOpenThreadSelection(settings: settings, modelContext: context))
    }

    func testResolvedLastOpenThreadSelectionIgnoresArchivedThreadsAndMismatchedConversations() throws {
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let project = Project(path: "/tmp/project", name: "Alveary")
        let archivedConversation = Conversation(title: "Archived", provider: "claude")
        let archivedThread = AgentThread(
            name: "Archived",
            archivedAt: Date(),
            project: project,
            conversations: [archivedConversation]
        )
        let activeConversation = Conversation(title: "Active", provider: "claude")
        let activeThread = AgentThread(name: "Active", project: project, conversations: [activeConversation])
        project.threads.append(archivedThread)
        project.threads.append(activeThread)
        context.insert(project)
        try context.save()

        var archivedSettings = AppSettings()
        archivedSettings.reopenLastThreadAndConversationOnLaunch = true
        archivedSettings.lastOpenThreadID = archivedThread.persistentModelID
        archivedSettings.lastOpenConversationID = archivedConversation.persistentModelID

        XCTAssertNil(resolvedLastOpenThreadSelection(settings: archivedSettings, modelContext: context))

        var mismatchedConversationSettings = AppSettings()
        mismatchedConversationSettings.reopenLastThreadAndConversationOnLaunch = true
        mismatchedConversationSettings.lastOpenThreadID = activeThread.persistentModelID
        mismatchedConversationSettings.lastOpenConversationID = archivedConversation.persistentModelID

        let selection = resolvedLastOpenThreadSelection(
            settings: mismatchedConversationSettings,
            modelContext: context
        )

        XCTAssertNil(selection)
    }

    func testResolvedLastOpenThreadSelectionReturnsNilWhenThreadOrConversationWasDeleted() throws {
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let project = Project(path: "/tmp/project", name: "Alveary")
        let conversation = Conversation(title: "Main", provider: "claude")
        let thread = AgentThread(name: "Toolbar Action", project: project, conversations: [conversation])
        project.threads.append(thread)
        context.insert(project)
        try context.save()

        var missingThreadSettings = AppSettings()
        missingThreadSettings.reopenLastThreadAndConversationOnLaunch = true
        missingThreadSettings.lastOpenThreadID = thread.persistentModelID
        missingThreadSettings.lastOpenConversationID = conversation.persistentModelID

        context.delete(thread)
        try context.save()

        XCTAssertNil(resolvedLastOpenThreadSelection(settings: missingThreadSettings, modelContext: context))

        let replacementProject = Project(path: "/tmp/replacement-project", name: "Replacement")
        let replacementConversation = Conversation(title: "Replacement", provider: "claude")
        let replacementThread = AgentThread(
            name: "Replacement",
            project: replacementProject,
            conversations: [replacementConversation]
        )
        replacementProject.threads.append(replacementThread)
        context.insert(replacementProject)
        try context.save()

        var missingConversationSettings = AppSettings()
        missingConversationSettings.reopenLastThreadAndConversationOnLaunch = true
        missingConversationSettings.lastOpenThreadID = replacementThread.persistentModelID
        missingConversationSettings.lastOpenConversationID = conversation.persistentModelID

        XCTAssertNil(resolvedLastOpenThreadSelection(settings: missingConversationSettings, modelContext: context))
    }

    func testProjectActionLaunchConfigurationUsesExecutionContextDirectoryAndCommand() throws {
        let project = Project(path: "/tmp/project", name: "Alveary")
        let thread = AgentThread(name: "Toolbar Action", worktreePath: "/tmp/worktree", project: project)
        let action = AlvearyProjectConfig.ProjectAction(name: "Build", command: "./scripts/build.sh")
        let context = try XCTUnwrap(ProjectActionExecutionContext(thread: thread, action: action))
        var builder = TerminalLaunchBuilder()
        builder.environment = {
            ["SHELL": "/bin/zsh"]
        }
        builder.homeDirectory = {
            "/Users/alice"
        }
        builder.userName = {
            "alice"
        }
        builder.passwdShell = {
            nil
        }
        builder.isExecutable = { path in
            path == "/bin/zsh"
        }

        let configuration = builder.projectAction(
            command: context.command,
            currentDirectory: context.currentDirectory
        )

        XCTAssertEqual(configuration.executable, "/bin/zsh")
        XCTAssertEqual(configuration.execName, "-zsh")
        XCTAssertEqual(configuration.args, [])
        XCTAssertEqual(configuration.projectActionCommand, "./scripts/build.sh")
        XCTAssertEqual(configuration.currentDirectory, "/tmp/worktree")
    }

    func testProjectActionTerminalPresentationDoesNotAutoExpandByDefault() {
        XCTAssertFalse(ProjectActionTerminalPresentation.shouldAutoExpand(settings: AppSettings()))
    }

    func testProjectActionTerminalPresentationAutoExpandsWhenEnabled() {
        var settings = AppSettings()
        settings.expandTerminalWhenActionsRun = true

        XCTAssertTrue(ProjectActionTerminalPresentation.shouldAutoExpand(settings: settings))
    }

    func testProjectActionTerminalPresentationUsesConfiguredMaxSessions() {
        var settings = AppSettings()
        settings.maxTerminalSessions = 12

        XCTAssertEqual(ProjectActionTerminalPresentation.maxSessions(settings: settings), 12)
    }

    func testPrimaryToolbarGroupWidthIncludesAnimatedProjectActionSlot() {
        let twoActionStripWidth = PrimaryToolbarGroupWidth.projectActionStripWidth(actionCount: 2)
        XCTAssertEqual(
            twoActionStripWidth,
            PrimaryToolbarMetrics.iconButtonSize * 2 + PrimaryToolbarMetrics.buttonSpacing
        )

        let twoActionSlotWidth = PrimaryToolbarGroupWidth.projectActionsSlotWidth(actionCount: 2)
        XCTAssertEqual(
            twoActionSlotWidth,
            twoActionStripWidth + PrimaryToolbarMetrics.buttonSpacing
        )

        let groupWidth = PrimaryToolbarGroupWidth.groupWidth(
            projectActionsSlotWidth: twoActionSlotWidth,
            diffStatusWidth: 42
        )
        XCTAssertEqual(
            groupWidth,
            PrimaryToolbarMetrics.containerHorizontalInset * 2
                + PrimaryToolbarMetrics.iconButtonSize * 3
                + PrimaryToolbarMetrics.buttonSpacing * 2
                + twoActionSlotWidth
                + 42
        )
    }
}

private struct DiffCommitTargetFixture {
    let context: ModelContext
    let appState: AppState
    let project: Project
    let thread: AgentThread
    let conversation: Conversation
}

@MainActor
private func makeDiffCommitTargetFixture(
    projectPath: String = "/tmp/project",
    projectName: String = "Alveary",
    worktreePath: String? = nil
) throws -> DiffCommitTargetFixture {
    let container = try ModelContainer(
        for: Project.self,
        AgentThread.self,
        Conversation.self,
        ConversationEventRecord.self,
        ScheduledTask.self,
        ScheduledTaskRun.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    let appState = AppState()
    let project = Project(
        path: projectPath,
        name: projectName,
        remoteName: "upstream",
        baseRef: "develop"
    )
    let conversation = Conversation(title: "Main", provider: "claude")
    let thread = AgentThread(
        name: "Toolbar Action",
        worktreePath: worktreePath,
        project: project,
        conversations: [conversation]
    )
    project.threads.append(thread)
    context.insert(project)
    try context.save()

    return DiffCommitTargetFixture(
        context: context,
        appState: appState,
        project: project,
        thread: thread,
        conversation: conversation
    )
}
