import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ScheduledTaskModelTests: XCTestCase {
    func testDefinitionFieldsAndRecurrenceRoundTrip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(path: "/tmp/scheduled-project", name: "Scheduled Project")
        let occurrence = Date(timeIntervalSince1970: 1_800_000_000)
        let task = ScheduledTask(
            id: "schedule-1",
            title: "Review changes",
            prompt: "Review the latest changes.",
            revision: 3,
            recurrence: .weekly(weekday: 2, hour: 9, minute: 30),
            timeZoneIdentifier: "America/Chicago",
            providerID: "codex",
            model: "gpt-5",
            effort: "high",
            permissionMode: "default",
            workspaceKind: .project,
            workspaceStrategy: .worktree,
            grantedRoots: ["/tmp/grant", "/tmp/../tmp/grant", "/tmp/second-grant"],
            project: project,
            nextOccurrenceAt: occurrence
        )
        project.scheduledTasks = [task]
        context.insert(project)
        try context.save()

        let fetchedTask = try XCTUnwrap(try context.fetch(FetchDescriptor<ScheduledTask>()).first)
        XCTAssertEqual(fetchedTask.id, "schedule-1")
        XCTAssertEqual(fetchedTask.revision, 3)
        XCTAssertEqual(fetchedTask.state, .active)
        XCTAssertEqual(fetchedTask.recurrence, .weekly(weekday: 2, hour: 9, minute: 30))
        XCTAssertEqual(fetchedTask.timeZoneIdentifier, "America/Chicago")
        XCTAssertEqual(fetchedTask.providerID, "codex")
        XCTAssertEqual(fetchedTask.model, "gpt-5")
        XCTAssertEqual(fetchedTask.workspaceKind, .project)
        XCTAssertEqual(fetchedTask.workspaceStrategy, .worktree)
        XCTAssertEqual(fetchedTask.grantedRoots, [
            CanonicalPath.normalize("/tmp/grant"),
            CanonicalPath.normalize("/tmp/second-grant")
        ])
        XCTAssertEqual(fetchedTask.project?.path, CanonicalPath.normalize("/tmp/scheduled-project"))
        XCTAssertEqual(fetchedTask.nextOccurrenceAt, occurrence)
        XCTAssertNil(fetchedTask.pendingOccurrenceAt)
    }

    func testEveryStructuredRecurrenceBridgesThroughFlatFields() {
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        let values: [ScheduledTaskRecurrence] = [
            .once(instant),
            .interval(minutes: 15, anchor: instant),
            .daily(hour: 8, minute: 5),
            .weekdays(days: [2, 4, 6], hour: 9, minute: 10),
            .weekly(weekday: 6, hour: 10, minute: 15),
            .monthly(day: 31, hour: 11, minute: 20)
        ]

        for recurrence in values {
            let task = makeTask(recurrence: recurrence)
            XCTAssertEqual(task.recurrence, recurrence)
        }
    }

    func testRunPersistsImmutableDefinitionSnapshotAndTaskProvenance() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let occurrence = Date(timeIntervalSince1970: 1_800_000_000)
        let project = Project(path: "/tmp/snapshot-project", name: "Snapshot Project")
        let task = makeTask(
            id: "definition",
            recurrence: .daily(hour: 8, minute: 0),
            project: project,
            grantedRoots: ["/tmp/snapshot-grant"]
        )
        let thread = AgentThread(
            name: "Scheduled run",
            hasCustomName: true,
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/prepared-workspace",
                ownershipStrategy: .privateOwned,
                ownershipMarkerID: "marker"
            )
        )
        let run = ScheduledTaskRun(
            snapshotting: task,
            occurrenceID: "definition:1800000000",
            triggerID: "trigger-1",
            occurrenceAt: occurrence,
            triggerKind: .scheduled,
            thread: thread
        )
        task.runs = [run]
        context.insert(task)
        context.insert(thread)
        try context.save()

        task.title = "Edited title"
        task.prompt = "Edited prompt"
        task.revision = 2
        try context.save()

        let fetchedRun = try XCTUnwrap(try context.fetch(FetchDescriptor<ScheduledTaskRun>()).first)
        XCTAssertEqual(fetchedRun.definitionID, "definition")
        XCTAssertEqual(fetchedRun.definitionRevision, 1)
        XCTAssertEqual(fetchedRun.titleSnapshot, "Scheduled definition")
        XCTAssertEqual(fetchedRun.promptSnapshot, "Perform the scheduled work.")
        XCTAssertEqual(fetchedRun.projectPathSnapshot, CanonicalPath.normalize("/tmp/snapshot-project"))
        XCTAssertEqual(fetchedRun.grantedRootsSnapshot, [CanonicalPath.normalize("/tmp/snapshot-grant")])
        XCTAssertEqual(fetchedRun.occurrenceAt, occurrence)
        XCTAssertEqual(fetchedRun.triggerKind, .scheduled)
        XCTAssertEqual(fetchedRun.status, .claimed)
        XCTAssertFalse(fetchedRun.status.isTerminal)
        XCTAssertEqual(fetchedRun.scheduledTask?.id, "definition")
        XCTAssertEqual(fetchedRun.thread?.name, "Scheduled run")
        XCTAssertEqual(fetchedRun.thread?.scheduledTaskRun?.id, fetchedRun.id)
    }

    func testDeletingDefinitionAndTaskThreadNullifiesRunRelationships() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let task = makeTask(id: "definition")
        let thread = AgentThread(name: "Scheduled run", mode: .task)
        let run = makeRun(task: task, thread: thread)
        task.runs = [run]
        context.insert(task)
        context.insert(thread)
        try context.save()

        context.delete(task)
        try context.save()

        var fetchedRun = try XCTUnwrap(try context.fetch(FetchDescriptor<ScheduledTaskRun>()).first)
        XCTAssertEqual(fetchedRun.definitionID, "definition")
        XCTAssertNil(fetchedRun.scheduledTask)
        XCTAssertEqual(fetchedRun.thread?.name, "Scheduled run")

        let fetchedThread = try XCTUnwrap(try context.fetch(FetchDescriptor<AgentThread>()).first)
        context.delete(fetchedThread)
        try context.save()

        fetchedRun = try XCTUnwrap(try context.fetch(FetchDescriptor<ScheduledTaskRun>()).first)
        XCTAssertNil(fetchedRun.thread)
    }

    func testDeletingRunNullifiesTaskThreadProvenance() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let task = makeTask(id: "definition")
        let thread = AgentThread(name: "Scheduled run", mode: .task)
        let run = makeRun(task: task, thread: thread)
        task.runs = [run]
        context.insert(task)
        context.insert(thread)
        try context.save()

        context.delete(run)
        try context.save()

        let fetchedThread = try XCTUnwrap(try context.fetch(FetchDescriptor<AgentThread>()).first)
        XCTAssertNil(fetchedThread.scheduledTaskRun)
        let fetchedTask = try XCTUnwrap(try context.fetch(FetchDescriptor<ScheduledTask>()).first)
        XCTAssertTrue(fetchedTask.runs.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledTaskRun>()), 0)
    }

    func testDefinitionRunAndProvenancePersistAcrossStoreReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScheduledTaskReopen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("Alveary.store"))

        try autoreleasepool {
            let container = try makeContainer(configuration: configuration)
            let context = container.mainContext
            let project = Project(path: "/tmp/reopen-project", name: "Reopen Project")
            let task = makeTask(id: "reopen-definition", project: project)
            let thread = AgentThread(name: "Reopened scheduled run", mode: .task)
            let run = ScheduledTaskRun(
                snapshotting: task,
                occurrenceID: "reopen-occurrence",
                triggerID: "reopen-trigger",
                occurrenceAt: Date(timeIntervalSince1970: 1_800_000_000),
                triggerKind: .scheduled,
                status: .success,
                thread: thread
            )
            project.scheduledTasks = [task]
            task.runs = [run]
            context.insert(project)
            context.insert(thread)
            try context.save()
        }

        try autoreleasepool {
            let container = try makeContainer(configuration: configuration)
            let context = container.mainContext
            let task = try XCTUnwrap(try context.fetch(FetchDescriptor<ScheduledTask>()).first)
            let run = try XCTUnwrap(try context.fetch(FetchDescriptor<ScheduledTaskRun>()).first)

            XCTAssertEqual(task.id, "reopen-definition")
            XCTAssertEqual(task.runs.map(\.id), [run.id])
            XCTAssertEqual(run.occurrenceID, "reopen-occurrence")
            XCTAssertEqual(run.triggerID, "reopen-trigger")
            XCTAssertEqual(run.status, .success)
            XCTAssertTrue(run.status.isTerminal)
            XCTAssertEqual(run.scheduledTask?.id, task.id)
            XCTAssertEqual(run.thread?.name, "Reopened scheduled run")
            XCTAssertEqual(run.thread?.scheduledTaskRun?.id, run.id)
        }
    }

    func testDeletingProjectNullifiesDefinitionButPreservesRunAndTaskThread() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(path: "/tmp/source", name: "Source")
        let projectThread = AgentThread(name: "Project thread", project: project)
        let task = makeTask(id: "definition", project: project)
        let taskThread = AgentThread(name: "Scheduled run", mode: .task)
        let run = makeRun(task: task, thread: taskThread)
        project.threads = [projectThread]
        project.scheduledTasks = [task]
        task.runs = [run]
        context.insert(project)
        context.insert(taskThread)
        try context.save()

        context.delete(project)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AgentThread>()).map(\.name), ["Scheduled run"])
        XCTAssertNil(try context.fetch(FetchDescriptor<ScheduledTask>()).first?.project)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledTaskRun>()), 1)
    }

    func testOccurrenceAndTriggerIdentitiesAreUnique() throws {
        let occurrenceContainer = try makeContainer()
        let occurrenceContext = ModelContext(occurrenceContainer)
        occurrenceContext.insert(makeRun(occurrenceID: "occurrence", triggerID: "trigger-1"))
        try occurrenceContext.save()
        occurrenceContext.insert(makeRun(occurrenceID: "occurrence", triggerID: "trigger-2"))
        try occurrenceContext.save()
        XCTAssertEqual(try occurrenceContext.fetchCount(FetchDescriptor<ScheduledTaskRun>()), 1)

        let triggerContainer = try makeContainer()
        let triggerContext = ModelContext(triggerContainer)
        triggerContext.insert(makeRun(occurrenceID: "occurrence-1", triggerID: "trigger"))
        try triggerContext.save()
        triggerContext.insert(makeRun(occurrenceID: "occurrence-2", triggerID: "trigger"))
        try triggerContext.save()
        XCTAssertEqual(try triggerContext.fetchCount(FetchDescriptor<ScheduledTaskRun>()), 1)
    }

    func testUnknownRawValuesFailClosed() {
        let task = makeTask()
        task.stateRawValue = "future-state"
        task.recurrenceKindRawValue = "future-recurrence"
        task.workspaceKindRawValue = "future-workspace"
        task.workspaceStrategyRawValue = "future-strategy"

        XCTAssertEqual(task.state, .paused)
        XCTAssertNil(task.recurrence)
        XCTAssertEqual(task.workspaceKind, .privateWorkspace)
        XCTAssertEqual(task.workspaceStrategy, .worktree)

        let run = makeRun()
        run.triggerKindRawValue = "future-trigger"
        run.statusRawValue = "future-status"
        XCTAssertEqual(run.triggerKind, .scheduled)
        XCTAssertEqual(run.status, .failure)
        XCTAssertTrue(run.status.isTerminal)
    }

    private func makeContainer(
        configuration: ModelConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
    ) throws -> ModelContainer {
        try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            configurations: configuration
        )
    }

    private func makeTask(
        id: String = UUID().uuidString,
        recurrence: ScheduledTaskRecurrence = .daily(hour: 9, minute: 0),
        project: Project? = nil,
        grantedRoots: [String] = []
    ) -> ScheduledTask {
        ScheduledTask(
            id: id,
            title: "Scheduled definition",
            prompt: "Perform the scheduled work.",
            recurrence: recurrence,
            timeZoneIdentifier: "America/Chicago",
            providerID: "codex",
            workspaceKind: project == nil ? .privateWorkspace : .project,
            grantedRoots: grantedRoots,
            project: project
        )
    }

    private func makeRun(
        task: ScheduledTask? = nil,
        thread: AgentThread? = nil,
        occurrenceID: String = UUID().uuidString,
        triggerID: String = UUID().uuidString,
        occurrenceAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> ScheduledTaskRun {
        ScheduledTaskRun(
            occurrenceID: occurrenceID,
            triggerID: triggerID,
            definitionID: task?.id ?? "definition",
            definitionRevision: task?.revision ?? 1,
            occurrenceAt: occurrenceAt,
            triggerKind: .scheduled,
            titleSnapshot: task?.title ?? "Scheduled definition",
            promptSnapshot: task?.prompt ?? "Perform the scheduled work.",
            timeZoneIdentifierSnapshot: task?.timeZoneIdentifier ?? "America/Chicago",
            providerIDSnapshot: task?.providerID ?? "codex",
            effortSnapshot: task?.effort ?? "medium",
            permissionModeSnapshot: task?.permissionMode ?? "default",
            workspaceKindSnapshot: task?.workspaceKind ?? .privateWorkspace,
            workspaceStrategySnapshot: task?.workspaceStrategy ?? .worktree,
            scheduledTask: task,
            thread: thread
        )
    }
}
