import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ContentViewProjectActionsTests {
    func testLinkedScheduledRunFallbackUsesWorkspaceSnapshotForProjectActionsAndCommitDiff() throws {
        let projectFixture = try makeFallbackScheduledProjectActionFixture(workspaceKind: .project)
        let privateFixture = try makeFallbackScheduledProjectActionFixture(workspaceKind: .privateWorkspace)
        let action = AlvearyProjectConfig.ProjectAction(name: "Build", command: "./scripts/build.sh")
        let projectWorktreePath = try XCTUnwrap(projectFixture.thread.worktreePath)

        let projectActionContext = try XCTUnwrap(ProjectActionExecutionContext(thread: projectFixture.thread, action: action))
        XCTAssertEqual(projectActionContext.currentDirectory, projectWorktreePath)
        XCTAssertTrue(SidebarItem.thread(projectFixture.thread).canCommitDiffChanges)
        let projectCommitTarget = try XCTUnwrap(DiffGitCommitTargetSnapshotResolver.resolve(
            selection: .thread(projectFixture.thread),
            modelContext: projectFixture.context,
            appState: projectFixture.appState,
            activeDirectory: projectWorktreePath
        ))
        XCTAssertEqual(projectCommitTarget.directory, projectWorktreePath)
        XCTAssertEqual(projectCommitTarget.generationRoute, .thread)

        XCTAssertNil(ProjectActionExecutionContext(thread: privateFixture.thread, action: action))
        XCTAssertFalse(SidebarItem.thread(privateFixture.thread).canCommitDiffChanges)
        XCTAssertNil(DiffGitCommitTargetSnapshotResolver.resolve(
            selection: .thread(privateFixture.thread),
            modelContext: privateFixture.context,
            appState: privateFixture.appState,
            activeDirectory: privateFixture.thread.worktreePath
        ))
    }

    func testLinkedScheduledRunFallbackUsesWorkspaceSnapshotForTerminalRoot() throws {
        let projectFixture = try makeFallbackScheduledProjectActionFixture(workspaceKind: .project)
        let privateFixture = try makeFallbackScheduledProjectActionFixture(workspaceKind: .privateWorkspace)
        let projectWorktreePath = try XCTUnwrap(projectFixture.thread.worktreePath)
        let projectShellContext = TerminalDefaultShellContextResolver.resolve(
            selection: .thread(projectFixture.thread),
            modelContext: projectFixture.context,
            builder: projectFixture.builder
        )
        let privateShellContext = TerminalDefaultShellContextResolver.resolve(
            selection: .thread(privateFixture.thread),
            modelContext: privateFixture.context,
            builder: privateFixture.builder
        )

        XCTAssertEqual(projectShellContext.threadID, projectFixture.thread.persistentModelID)
        XCTAssertEqual(projectShellContext.currentDirectory, projectWorktreePath)
        XCTAssertEqual(privateShellContext.threadID, privateFixture.thread.persistentModelID)
        XCTAssertEqual(privateShellContext.currentDirectory, "/Users/alice")

        projectFixture.thread.isDraft = true
        privateFixture.thread.isDraft = true
        try projectFixture.context.save()
        try privateFixture.context.save()
        let projectDraftShellContext = TerminalDefaultShellContextResolver.resolve(
            selection: .thread(projectFixture.thread),
            modelContext: projectFixture.context,
            builder: projectFixture.builder
        )
        let privateDraftShellContext = TerminalDefaultShellContextResolver.resolve(
            selection: .thread(privateFixture.thread),
            modelContext: privateFixture.context,
            builder: privateFixture.builder
        )
        XCTAssertEqual(projectDraftShellContext.currentDirectory, projectFixture.project.path)
        XCTAssertEqual(privateDraftShellContext.currentDirectory, "/Users/alice")
    }
}

private struct FallbackScheduledProjectActionFixture {
    let container: ModelContainer
    let context: ModelContext
    let project: Project
    let thread: AgentThread
    let appState: AppState
    let builder: TerminalLaunchBuilder
}

@MainActor
private func makeFallbackScheduledProjectActionFixture(
    workspaceKind: ScheduledTaskWorkspaceKind
) throws -> FallbackScheduledProjectActionFixture {
    let container = try ModelContainer(
        for: Project.self,
        AgentThread.self,
        Conversation.self,
        ConversationEventRecord.self,
        ScheduledTask.self,
        ScheduledTaskRun.self,
        ScheduledTaskProposal.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    let project = Project(path: "/tmp/fallback-scheduled-project", name: "Project")
    let run = makeProjectActionsScheduledRun(workspaceKind: workspaceKind)
    let thread = AgentThread(
        name: "Fallback scheduled task",
        worktreePath: "/tmp/fallback-scheduled-worktree",
        project: project,
        scheduledTaskRun: run
    )
    let conversation = Conversation(id: "fallback-scheduled-conversation", isMain: true, thread: thread)
    thread.conversations = [conversation]
    thread.modeRawValue = "future-mode"
    run.thread = thread
    project.threads = [thread]
    context.insert(project)
    context.insert(run)
    try context.save()
    let appState = AppState()
    appState.selectedConversationIDs[thread.persistentModelID] = conversation.persistentModelID
    var builder = TerminalLaunchBuilder()
    builder.homeDirectory = { "/Users/alice" }
    return FallbackScheduledProjectActionFixture(
        container: container,
        context: context,
        project: project,
        thread: thread,
        appState: appState,
        builder: builder
    )
}

private func makeProjectActionsScheduledRun(workspaceKind: ScheduledTaskWorkspaceKind) -> ScheduledTaskRun {
    ScheduledTaskRun(
        occurrenceID: UUID().uuidString,
        definitionID: "project-actions-definition",
        definitionRevision: 1,
        occurrenceAt: Date(timeIntervalSinceReferenceDate: 1_000),
        triggerKind: .scheduled,
        status: .success,
        titleSnapshot: "Scheduled task",
        promptSnapshot: "Run scheduled work.",
        timeZoneIdentifierSnapshot: "UTC",
        providerIDSnapshot: "codex",
        effortSnapshot: "high",
        permissionModeSnapshot: "default",
        workspaceKindSnapshot: workspaceKind,
        workspaceStrategySnapshot: .worktree
    )
}
