import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ContentViewProjectActionsTests {
    func testToolbarProjectActionsSelectionDerivesFromSelectionTokens() {
        let project = Project(path: "/tmp/project", name: "Alveary")
        let thread = AgentThread(name: "Thread", project: project)

        XCTAssertEqual(
            ToolbarProjectActionsSelection(selection: .thread(thread)),
            .thread(thread.persistentModelID)
        )
        XCTAssertEqual(
            ToolbarProjectActionsSelection(selection: .project(project)),
            .project(project.persistentModelID)
        )
        XCTAssertEqual(ToolbarProjectActionsSelection(selection: .settings), .none)
        XCTAssertEqual(ToolbarProjectActionsSelection(selection: .skills), .none)
        XCTAssertEqual(ToolbarProjectActionsSelection(selection: nil), .none)
    }

    func testToolbarProjectActionsSelectionCapabilityCoversThreadsAndProjects() {
        let project = Project(path: "/tmp/project", name: "Alveary")
        let thread = AgentThread(name: "Thread", project: project)

        XCTAssertTrue(ToolbarProjectActionsSelection(selection: .project(project)).isProjectActionCapable)
        XCTAssertTrue(ToolbarProjectActionsSelection(selection: .thread(thread)).isProjectActionCapable)
        XCTAssertFalse(ToolbarProjectActionsSelection(selection: .settings).isProjectActionCapable)
    }

    func testToolbarProjectActionsTargetResolverResolvesProjectRowByIdentity() throws {
        let fixture = try makeToolbarProjectActionsFixture()

        let target = ToolbarProjectActionsTargetResolver.resolve(
            key: .project(fixture.project.persistentModelID),
            modelContext: fixture.context
        )

        XCTAssertEqual(target?.projectPath, "/tmp/toolbar-owner-project")
        XCTAssertEqual(target?.owner, .folder(
            .project(fixture.project.id), try XCTUnwrap(fixture.project.workspaceFolderTargets.first)
        ))
    }

    func testToolbarProjectActionsTargetResolverResolvesMaterializedThreadToThreadOwner() throws {
        let fixture = try makeToolbarProjectActionsFixture()

        let target = ToolbarProjectActionsTargetResolver.resolve(
            key: .thread(fixture.thread.persistentModelID),
            modelContext: fixture.context
        )

        XCTAssertEqual(target?.projectPath, "/tmp/toolbar-owner-project")
        XCTAssertEqual(target?.owner, .folder(
            .thread(fixture.thread.persistentModelID), try XCTUnwrap(fixture.thread.workspaceFolderTargets.first)
        ))
    }

    func testToolbarProjectActionsTargetResolverResolvesDraftThreadToProjectOwner() throws {
        let fixture = try makeToolbarProjectActionsFixture()
        fixture.thread.isDraft = true
        try fixture.context.save()

        let target = ToolbarProjectActionsTargetResolver.resolve(
            key: .thread(fixture.thread.persistentModelID),
            modelContext: fixture.context
        )

        // A draft has no worktree yet, so its actions run at the project root.
        XCTAssertEqual(target?.projectPath, "/tmp/toolbar-owner-project")
        XCTAssertEqual(target?.owner, .folder(
            .thread(fixture.thread.persistentModelID), try XCTUnwrap(fixture.thread.workspaceFolderTargets.first)
        ))
    }

    func testToolbarProjectActionsTargetResolverRejectsArchivedTaskModeAndProjectlessThreads() throws {
        let fixture = try makeToolbarProjectActionsFixture()

        XCTAssertNil(ToolbarProjectActionsTargetResolver.resolve(key: .none, modelContext: fixture.context))

        fixture.thread.archivedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        try fixture.context.save()
        XCTAssertNil(ToolbarProjectActionsTargetResolver.resolve(
            key: .thread(fixture.thread.persistentModelID),
            modelContext: fixture.context
        ))

        fixture.thread.archivedAt = nil
        fixture.thread.mode = .task
        try fixture.context.save()
        XCTAssertNil(ToolbarProjectActionsTargetResolver.resolve(
            key: .thread(fixture.thread.persistentModelID),
            modelContext: fixture.context
        ))

        let projectless = AgentThread(name: "No Project")
        fixture.context.insert(projectless)
        try fixture.context.save()
        XCTAssertNil(ToolbarProjectActionsTargetResolver.resolve(
            key: .thread(projectless.persistentModelID),
            modelContext: fixture.context
        ))
    }

    func testProjectActionExecutionContextForProjectRowRunsAtProjectRootWithoutThread() {
        let action = AlvearyProjectConfig.ProjectAction(icon: "hammer", name: "Build", command: "./scripts/build.sh")

        let context = ProjectActionExecutionContext(
            folder: WorkspaceFolderTarget(directory: "/tmp/project", source: SourceFolderSnapshot(path: "/tmp/project"), isPrimary: true),
            thread: nil, action: action
        )

        XCTAssertEqual(context.title, "Build")
        XCTAssertNil(context.threadID)
        XCTAssertNil(context.threadName)
        XCTAssertEqual(context.currentDirectory, "/tmp/project")
        XCTAssertEqual(context.command, "./scripts/build.sh")
    }

    func testProjectActionLaunchConfigurationForProjectRowUsesProjectRoot() {
        let action = AlvearyProjectConfig.ProjectAction(name: "Build", command: "./scripts/build.sh")
        let context = ProjectActionExecutionContext(
            folder: WorkspaceFolderTarget(directory: "/tmp/project", source: SourceFolderSnapshot(path: "/tmp/project"), isPrimary: true),
            thread: nil, action: action
        )

        let configuration = TerminalLaunchBuilder().projectAction(
            command: context.command,
            currentDirectory: context.currentDirectory
        )

        XCTAssertEqual(configuration.currentDirectory, "/tmp/project")
    }

    func testProjectActionSymbolsRenderForProjectOwnersAndSurviveSelectionSwitches() {
        let actions = [
            AlvearyProjectConfig.ProjectAction(icon: "hammer", name: "Build", command: "build"),
            AlvearyProjectConfig.ProjectAction(name: "Test", command: "test")
        ]

        XCTAssertEqual(
            PrimaryToolbarButtonGroup.projectActionSymbols(
                isSelectionProjectActionCapable: true,
                projectActions: actions,
                projectActionsOwner: .folder(.project("project"), WorkspaceFolderTarget(
                    directory: "/tmp/project", source: SourceFolderSnapshot(path: "/tmp/project"), isPrimary: true
                ))
            ),
            ["hammer", PrimaryToolbarButtonGroup.defaultProjectActionSymbol]
        )

        // A selection that cannot own actions collapses the slot even while the
        // previous selection's actions are still loaded.
        XCTAssertEqual(
            PrimaryToolbarButtonGroup.projectActionSymbols(
                isSelectionProjectActionCapable: false,
                projectActions: actions,
                projectActionsOwner: .folder(.project("project"), WorkspaceFolderTarget(
                    directory: "/tmp/project", source: SourceFolderSnapshot(path: "/tmp/project"), isPrimary: true
                ))
            ),
            []
        )

        // Actions loaded for a previous owner stay rendered while the newly
        // selected one resolves, so a same-project switch does not flash the slot.
        XCTAssertEqual(
            PrimaryToolbarButtonGroup.projectActionSymbols(
                isSelectionProjectActionCapable: true,
                projectActions: actions,
                projectActionsOwner: .folder(.project("previous"), WorkspaceFolderTarget(
                    directory: "/tmp/previously-loaded-project", source: SourceFolderSnapshot(path: "/tmp/previously-loaded-project"), isPrimary: true
                ))
            ).count,
            2
        )

        XCTAssertEqual(
            PrimaryToolbarButtonGroup.projectActionSymbols(
                isSelectionProjectActionCapable: true,
                projectActions: actions,
                projectActionsOwner: nil
            ),
            []
        )
    }
}

private struct ToolbarProjectActionsFixture {
    let container: ModelContainer
    let context: ModelContext
    let project: Project
    let thread: AgentThread
}

@MainActor
private func makeToolbarProjectActionsFixture() throws -> ToolbarProjectActionsFixture {
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
    let project = Project(path: "/tmp/toolbar-owner-project", name: "Alveary")
    let thread = AgentThread(name: "Toolbar Action", worktreePath: "/tmp/toolbar-owner-worktree", project: project)
    project.threads = [thread]
    context.insert(project)
    try context.save()

    return ToolbarProjectActionsFixture(container: container, context: context, project: project, thread: thread)
}
