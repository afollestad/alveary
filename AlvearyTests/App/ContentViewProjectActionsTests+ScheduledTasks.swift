import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ContentViewProjectActionsTests {
    func testLinkedScheduledRunWithFallbackModeCannotUseProjectActionsOrCommitDiff() throws {
        let fixture = try makeFallbackScheduledProjectActionFixture()
        let action = AlvearyProjectConfig.ProjectAction(name: "Build", command: "./scripts/build.sh")

        XCTAssertNil(ProjectActionExecutionContext(thread: fixture.thread, action: action))
        XCTAssertFalse(SidebarItem.thread(fixture.thread).canCommitDiffChanges)
        XCTAssertNil(DiffGitCommitTargetSnapshotResolver.resolve(
            selection: .thread(fixture.thread),
            modelContext: fixture.context,
            appState: fixture.appState,
            activeDirectory: fixture.thread.worktreePath
        ))
    }

    func testLinkedScheduledRunWithFallbackModeNeverUsesProjectTerminalRoot() throws {
        let fixture = try makeFallbackScheduledProjectActionFixture()
        let shellContext = TerminalDefaultShellContextResolver.resolve(
            selection: .thread(fixture.thread),
            modelContext: fixture.context,
            builder: fixture.builder
        )

        XCTAssertEqual(shellContext.threadID, fixture.thread.persistentModelID)
        XCTAssertEqual(shellContext.currentDirectory, "/Users/alice")
        XCTAssertNotEqual(shellContext.currentDirectory, fixture.project.path)
        XCTAssertNotEqual(shellContext.currentDirectory, fixture.thread.worktreePath)

        fixture.thread.isDraft = true
        try fixture.context.save()
        let draftShellContext = TerminalDefaultShellContextResolver.resolve(
            selection: .thread(fixture.thread),
            modelContext: fixture.context,
            builder: fixture.builder
        )
        XCTAssertEqual(draftShellContext.currentDirectory, "/Users/alice")
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
private func makeFallbackScheduledProjectActionFixture() throws -> FallbackScheduledProjectActionFixture {
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
    let project = Project(path: "/tmp/fallback-scheduled-project", name: "Project")
    let run = makeProjectActionsScheduledRun()
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

private func makeProjectActionsScheduledRun() -> ScheduledTaskRun {
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
        workspaceKindSnapshot: .project,
        workspaceStrategySnapshot: .worktree
    )
}
