import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testProjectDeletionPausesAndDetachesSchedulesWhilePreservingRunTask() throws {
        let fixture = try SidebarTestFixture()
        let actionDate = Date(timeIntervalSince1970: 1_000)
        let graph = try ScheduledProjectDeletionGraph.insert(into: fixture.context)

        let snapshot = try fixture.viewModel.makeProjectDeletionSnapshot(graph.project)
        try fixture.viewModel.commitProjectDeletion(snapshot, at: actionDate)

        XCTAssertNil(fixture.context.resolveProject(id: graph.projectID))
        XCTAssertNil(fixture.context.resolveThread(id: graph.projectThreadID))
        let survivingDefinition = try XCTUnwrap(
            fixture.context.resolveScheduledTask(id: graph.definition.id)
        )
        XCTAssertEqual(survivingDefinition.state, .paused)
        XCTAssertNil(survivingDefinition.project)
        XCTAssertNil(survivingDefinition.nextOccurrenceAt)
        XCTAssertNil(survivingDefinition.pendingOccurrenceAt)
        XCTAssertEqual(survivingDefinition.pauseReason, ScheduledTask.projectDeletedPauseReason)
        XCTAssertEqual(survivingDefinition.revision, 2)
        XCTAssertEqual(survivingDefinition.modifiedAt, actionDate)
        XCTAssertEqual(graph.run.status, ScheduledTaskRunStatus.running)
        XCTAssertEqual(graph.run.projectPathSnapshot, "/tmp/scheduled-project-delete")
        XCTAssertEqual(graph.run.thread?.persistentModelID, graph.taskThreadID)
        XCTAssertNotNil(fixture.context.resolveThread(id: graph.taskThreadID))
        XCTAssertEqual(graph.completedRun.status, ScheduledTaskRunStatus.success)
        XCTAssertEqual(graph.completedRun.thread?.persistentModelID, graph.completedTaskThreadID)
        XCTAssertNotNil(fixture.context.resolveThread(id: graph.completedTaskThreadID))
    }

    func testProjectDeletionPreservesLinkedRunTaskWhenModeFallsBackToProject() throws {
        let fixture = try SidebarTestFixture()
        let graph = try ScheduledProjectDeletionGraph.insert(into: fixture.context)
        let taskThread = try XCTUnwrap(graph.run.thread)
        let taskThreadID = taskThread.persistentModelID
        let runID = graph.run.persistentModelID
        let taskPrimaryRoot = taskThread.taskPrimaryRoot
        taskThread.modeRawValue = "future-mode"
        taskThread.project = graph.project
        try fixture.context.save()

        let snapshot = try fixture.viewModel.makeProjectDeletionSnapshot(graph.project)

        XCTAssertTrue(snapshot.detachedTaskThreadIDs.contains(taskThreadID))
        XCTAssertFalse(snapshot.threadSnapshots.contains { $0.threadID == taskThreadID })

        try fixture.viewModel.commitProjectDeletion(
            snapshot,
            at: Date(timeIntervalSince1970: 1_000)
        )

        let retainedThread = try XCTUnwrap(fixture.context.resolveThread(id: taskThreadID))
        XCTAssertEqual(retainedThread.modeRawValue, "future-mode")
        XCTAssertEqual(retainedThread.taskPrimaryRoot, taskPrimaryRoot)
        XCTAssertNil(retainedThread.project)
        XCTAssertEqual(
            fixture.context.resolveScheduledTaskRun(id: runID)?.thread?.persistentModelID,
            taskThreadID
        )
    }

    func testProjectDeletionRollsBackSchedulePauseAndDetachWhenCommitFails() throws {
        let fixture = try SidebarTestFixture(
            saveDeletionCommit: { _ in
                throw ScheduledProjectDeletionTestError.saveFailed
            }
        )
        let graph = try ScheduledProjectDeletionGraph.insert(into: fixture.context)
        let snapshot = try fixture.viewModel.makeProjectDeletionSnapshot(graph.project)

        XCTAssertThrowsError(
            try fixture.viewModel.commitProjectDeletion(
                snapshot,
                at: Date(timeIntervalSince1970: 1_000)
            )
        )

        XCTAssertNotNil(fixture.context.resolveProject(id: graph.projectID))
        let definition = try XCTUnwrap(
            fixture.context.resolveScheduledTask(id: graph.definition.id)
        )
        XCTAssertEqual(definition.state, .active)
        XCTAssertEqual(definition.project?.persistentModelID, graph.projectID)
        XCTAssertEqual(definition.nextOccurrenceAt, Date(timeIntervalSince1970: 900))
        XCTAssertEqual(definition.pendingOccurrenceAt, Date(timeIntervalSince1970: 950))
        XCTAssertNil(definition.pauseReason)
        XCTAssertEqual(definition.revision, 1)
    }

    func testProjectDeletedScheduleCannotResumeUntilProjectIsReattached() throws {
        let fixture = try SidebarTestFixture()
        let graph = try ScheduledProjectDeletionGraph.insert(into: fixture.context)
        let snapshot = try fixture.viewModel.makeProjectDeletionSnapshot(graph.project)
        try fixture.viewModel.commitProjectDeletion(
            snapshot,
            at: Date(timeIntervalSince1970: 1_000)
        )
        let service = ScheduledTaskMutationService(modelContext: fixture.context)

        XCTAssertThrowsError(
            try service.resume(
                definitionID: graph.definition.id,
                expectedRevision: 2,
                at: Date(timeIntervalSince1970: 2_000)
            )
        ) { error in
            XCTAssertEqual(error as? ScheduledTaskMutationError, .projectWorkspaceRequiresProject)
        }

        let definition = try XCTUnwrap(
            fixture.context.resolveScheduledTask(id: graph.definition.id)
        )
        XCTAssertEqual(definition.state, .paused)
        XCTAssertNil(definition.project)
        XCTAssertEqual(definition.pauseReason, ScheduledTask.projectDeletedPauseReason)
        XCTAssertEqual(definition.revision, 2)
        XCTAssertEqual(definition.modifiedAt, Date(timeIntervalSince1970: 1_000))
    }
}

private enum ScheduledProjectDeletionTestError: Error {
    case saveFailed
}

@MainActor
private struct ScheduledProjectDeletionGraph {
    let project: Project
    let definition: ScheduledTask
    let run: ScheduledTaskRun
    let completedRun: ScheduledTaskRun
    let projectID: PersistentIdentifier
    let projectThreadID: PersistentIdentifier
    let taskThreadID: PersistentIdentifier
    let completedTaskThreadID: PersistentIdentifier

    static func insert(into context: ModelContext) throws -> Self {
        let project = Project(path: "/tmp/scheduled-project-delete", name: "Scheduled")
        let projectThread = AgentThread(name: "Ordinary project thread", project: project)
        let definition = makeDefinition(project: project)
        let taskThread = makeTaskThread(
            primaryRoot: "/tmp/scheduled-project-delete-active-worktree",
            sourceProjectPath: project.path
        )
        let completedTaskThread = makeTaskThread(
            primaryRoot: "/tmp/scheduled-project-delete-completed-worktree",
            sourceProjectPath: project.path
        )
        let run = makeRun(
            occurrenceID: "scheduled-project-active-occurrence",
            status: .running,
            definition: definition,
            project: project,
            thread: taskThread
        )
        let completedRun = makeRun(
            occurrenceID: "scheduled-project-completed-occurrence",
            status: .success,
            definition: definition,
            project: project,
            thread: completedTaskThread
        )
        project.threads = [projectThread]
        project.scheduledTasks = [definition]
        definition.runs = [run, completedRun]
        taskThread.scheduledTaskRun = run
        completedTaskThread.scheduledTaskRun = completedRun
        context.insert(project)
        context.insert(taskThread)
        context.insert(completedTaskThread)
        context.insert(run)
        context.insert(completedRun)
        try context.save()
        return Self(
            project: project,
            definition: definition,
            run: run,
            completedRun: completedRun,
            projectID: project.persistentModelID,
            projectThreadID: projectThread.persistentModelID,
            taskThreadID: taskThread.persistentModelID,
            completedTaskThreadID: completedTaskThread.persistentModelID
        )
    }

    private static func makeDefinition(project: Project) -> ScheduledTask {
        ScheduledTask(
            id: "scheduled-project-definition",
            title: "Project schedule",
            prompt: "Run the checks",
            recurrence: .daily(hour: 8, minute: 0),
            timeZoneIdentifier: "UTC",
            providerID: "codex",
            workspaceKind: .project,
            workspaceStrategy: .worktree,
            project: project,
            nextOccurrenceAt: Date(timeIntervalSince1970: 900),
            pendingOccurrenceAt: Date(timeIntervalSince1970: 950)
        )
    }

    private static func makeTaskThread(
        primaryRoot: String,
        sourceProjectPath: String
    ) -> AgentThread {
        AgentThread(
            name: "Scheduled run task",
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: primaryRoot,
                ownershipStrategy: .projectWorktreeOwned,
                sourceProjectPath: sourceProjectPath
            )
        )
    }

    private static func makeRun(
        occurrenceID: String,
        status: ScheduledTaskRunStatus,
        definition: ScheduledTask,
        project: Project,
        thread: AgentThread
    ) -> ScheduledTaskRun {
        ScheduledTaskRun(
            occurrenceID: occurrenceID,
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: Date(timeIntervalSince1970: 900),
            triggerKind: .scheduled,
            status: status,
            titleSnapshot: definition.title,
            promptSnapshot: definition.prompt,
            timeZoneIdentifierSnapshot: definition.timeZoneIdentifier,
            providerIDSnapshot: definition.providerID,
            effortSnapshot: definition.effort,
            permissionModeSnapshot: definition.permissionMode,
            workspaceKindSnapshot: definition.workspaceKind,
            workspaceStrategySnapshot: definition.workspaceStrategy,
            projectPathSnapshot: project.path,
            scheduledTask: definition,
            thread: thread
        )
    }
}
