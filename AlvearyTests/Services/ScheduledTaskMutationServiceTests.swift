import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ScheduledTaskMutationServiceTests: XCTestCase {
    func testPauseClearsPendingOccurrenceAndRecomputesStrictlyAfterAction() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let actionDate = Date(timeIntervalSince1970: 600)
        let definition = try fixture.insertDefinition(
            recurrence: .interval(minutes: 5, anchor: Date(timeIntervalSince1970: 0)),
            nextOccurrenceAt: Date(timeIntervalSince1970: 300),
            pendingOccurrenceAt: Date(timeIntervalSince1970: 540)
        )

        try fixture.service.pause(
            definitionID: definition.id,
            expectedRevision: 1,
            at: actionDate
        )

        XCTAssertEqual(definition.state, .paused)
        XCTAssertEqual(definition.nextOccurrenceAt, Date(timeIntervalSince1970: 900))
        XCTAssertNil(definition.pendingOccurrenceAt)
        XCTAssertEqual(definition.revision, 2)
        XCTAssertEqual(definition.modifiedAt, actionDate)
    }

    func testPauseIsIdempotentForBlockedDefinitionAndPreservesReason() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let modifiedAt = Date(timeIntervalSince1970: 500)
        let definition = try fixture.insertDefinition(
            state: .paused,
            nextOccurrenceAt: Date(timeIntervalSince1970: 900),
            pauseReason: "Source project was deleted.",
            lastError: "Project is missing"
        )
        definition.modifiedAt = modifiedAt
        try fixture.context.save()

        try fixture.service.pause(
            definitionID: definition.id,
            expectedRevision: 1,
            at: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(definition.state, .paused)
        XCTAssertEqual(definition.nextOccurrenceAt, Date(timeIntervalSince1970: 900))
        XCTAssertEqual(definition.pauseReason, "Source project was deleted.")
        XCTAssertEqual(definition.lastError, "Project is missing")
        XCTAssertEqual(definition.revision, 1)
        XCTAssertEqual(definition.modifiedAt, modifiedAt)
    }

    func testEditChangesOnlyFutureDefinitionAndRetainsActiveRunSnapshot() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let actionDate = Date(timeIntervalSince1970: 600)
        let definition = try fixture.insertDefinition(
            recurrence: .daily(hour: 8, minute: 0),
            nextOccurrenceAt: Date(timeIntervalSince1970: 700),
            pendingOccurrenceAt: Date(timeIntervalSince1970: 500)
        )
        let run = fixture.makeRun(definition: definition, status: .running)
        definition.runs = [run]
        fixture.context.insert(run)
        try fixture.context.save()

        try fixture.service.edit(
            definitionID: definition.id,
            expectedRevision: 1,
            edit: ScheduledTaskDefinitionEdit(
                title: "Updated",
                prompt: "Updated prompt",
                recurrence: .interval(minutes: 10, anchor: Date(timeIntervalSince1970: 0)),
                timeZoneIdentifier: "UTC",
                providerID: "claude",
                model: "model-2",
                effort: "high",
                permissionMode: "acceptEdits",
                workspaceKind: .privateWorkspace,
                workspaceStrategy: .worktree,
                grantedRoots: ["/tmp/grant", "/tmp/grant/"],
                project: nil
            ),
            at: actionDate
        )

        XCTAssertEqual(definition.title, "Updated")
        XCTAssertEqual(definition.prompt, "Updated prompt")
        XCTAssertEqual(definition.nextOccurrenceAt, Date(timeIntervalSince1970: 1_200))
        XCTAssertNil(definition.pendingOccurrenceAt)
        XCTAssertEqual(definition.grantedRoots, ["/tmp/grant"])
        XCTAssertEqual(definition.revision, 2)
        XCTAssertEqual(run.definitionRevision, 1)
        XCTAssertEqual(run.titleSnapshot, "Original")
        XCTAssertEqual(run.promptSnapshot, "Original prompt")
        XCTAssertEqual(run.providerIDSnapshot, "codex")
        XCTAssertEqual(run.status, .running)
    }

    func testEditPreservesPausedStateButClearsStalePauseDiagnostics() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let definition = try fixture.insertDefinition(
            state: .paused,
            recurrence: .daily(hour: 8, minute: 0),
            pauseReason: "Provider unavailable",
            lastError: "Missing provider"
        )

        try fixture.service.edit(
            definitionID: definition.id,
            edit: ScheduledTaskDefinitionEdit(
                title: definition.title,
                prompt: definition.prompt,
                recurrence: .daily(hour: 9, minute: 30),
                timeZoneIdentifier: "UTC",
                providerID: "codex",
                model: nil,
                effort: "medium",
                permissionMode: "default",
                workspaceKind: .privateWorkspace,
                workspaceStrategy: .worktree,
                grantedRoots: [],
                project: nil
            ),
            at: Date(timeIntervalSince1970: 600)
        )

        XCTAssertEqual(definition.state, .paused)
        XCTAssertNil(definition.pauseReason)
        XCTAssertNil(definition.lastError)
    }

    func testResumeSkipsPausedOccurrencesAndCompletesExpiredOneShot() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let actionDate = Date(timeIntervalSince1970: 600)
        let recurring = try fixture.insertDefinition(
            id: "recurring",
            state: .paused,
            recurrence: .interval(minutes: 5, anchor: Date(timeIntervalSince1970: 0)),
            nextOccurrenceAt: Date(timeIntervalSince1970: 300),
            pendingOccurrenceAt: Date(timeIntervalSince1970: 540),
            pauseReason: "Paused"
        )
        let expiredOneShot = try fixture.insertDefinition(
            id: "one-shot",
            state: .paused,
            recurrence: .once(Date(timeIntervalSince1970: 500)),
            nextOccurrenceAt: Date(timeIntervalSince1970: 500)
        )

        try fixture.service.resume(definitionID: recurring.id, at: actionDate)
        try fixture.service.resume(definitionID: expiredOneShot.id, at: actionDate)

        XCTAssertEqual(recurring.state, .active)
        XCTAssertEqual(recurring.nextOccurrenceAt, Date(timeIntervalSince1970: 900))
        XCTAssertNil(recurring.pendingOccurrenceAt)
        XCTAssertNil(recurring.pauseReason)
        XCTAssertEqual(expiredOneShot.state, .completed)
        XCTAssertNil(expiredOneShot.nextOccurrenceAt)
    }

    func testPauseRejectsCompletedOneShotWithoutChangingIt() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let definition = try fixture.insertDefinition(
            state: .completed,
            recurrence: .once(Date(timeIntervalSince1970: 500))
        )

        XCTAssertThrowsError(
            try fixture.service.pause(definitionID: definition.id)
        ) { error in
            XCTAssertEqual(error as? ScheduledTaskMutationError, .scheduleIsCompleted)
        }
        XCTAssertEqual(definition.state, .completed)
        XCTAssertEqual(definition.revision, 1)
    }

    func testRunNowUsesLatestDueOccurrenceWithoutChangingCadenceOrState() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let definition = try fixture.insertDefinition(
            state: .paused,
            recurrence: .interval(minutes: 5, anchor: Date(timeIntervalSince1970: 0)),
            nextOccurrenceAt: Date(timeIntervalSince1970: 300),
            pendingOccurrenceAt: Date(timeIntervalSince1970: 540)
        )
        let terminalRun = fixture.makeRun(definition: definition, status: .success)
        definition.runs = [terminalRun]
        fixture.context.insert(terminalRun)
        try fixture.context.save()

        let request = try fixture.service.prepareRunNow(
            definitionID: definition.id,
            at: Date(timeIntervalSince1970: 600)
        )

        XCTAssertEqual(request.occurrenceAt, Date(timeIntervalSince1970: 540))
        XCTAssertEqual(request.triggeredAt, Date(timeIntervalSince1970: 600))
        XCTAssertEqual(request.occurrenceSource, .pending)
        XCTAssertTrue(request.consumesScheduledOccurrence)
        XCTAssertEqual(definition.state, .paused)
        XCTAssertEqual(definition.nextOccurrenceAt, Date(timeIntervalSince1970: 300))
        XCTAssertEqual(definition.pendingOccurrenceAt, Date(timeIntervalSince1970: 540))
        XCTAssertEqual(definition.revision, 1)
    }

    func testRunNowUsesManualOccurrenceForCompletedDefinitionWithNoDueOccurrence() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let definition = try fixture.insertDefinition(
            state: .completed,
            recurrence: .once(Date(timeIntervalSince1970: 500))
        )
        let actionDate = Date(timeIntervalSince1970: 600)

        let request = try fixture.service.prepareRunNow(
            definitionID: definition.id,
            at: actionDate
        )

        XCTAssertEqual(request.occurrenceAt, actionDate)
        XCTAssertEqual(request.occurrenceSource, .manual)
        XCTAssertFalse(request.consumesScheduledOccurrence)
        XCTAssertEqual(definition.state, .completed)
    }

    func testRunNowConsumesDueNextOccurrence() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let dueDate = Date(timeIntervalSince1970: 300)
        let definition = try fixture.insertDefinition(
            nextOccurrenceAt: dueDate
        )

        let request = try fixture.service.prepareRunNow(
            definitionID: definition.id,
            at: Date(timeIntervalSince1970: 600)
        )

        XCTAssertEqual(request.occurrenceAt, dueDate)
        XCTAssertEqual(request.occurrenceSource, .scheduled)
        XCTAssertTrue(request.consumesScheduledOccurrence)
    }

    func testRunNowRejectsEveryActiveRunStatus() throws {
        for status in [
            ScheduledTaskRunStatus.claimed,
            .preparing,
            .running,
            .waiting
        ] {
            let fixture = try ScheduledTaskMutationFixture()
            let definition = try fixture.insertDefinition()
            let run = fixture.makeRun(definition: definition, status: status)
            definition.runs = [run]
            fixture.context.insert(run)
            try fixture.context.save()

            XCTAssertThrowsError(
                try fixture.service.prepareRunNow(definitionID: definition.id)
            ) { error in
                XCTAssertEqual(error as? ScheduledTaskMutationError, .runNowBlockedByActiveRun)
            }
        }
    }

    func testDeleteRetainsRunAndTaskThreadWithNullifiedDefinitionRelationship() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let definition = try fixture.insertDefinition()
        let thread = AgentThread(
            name: "Run task",
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/scheduled-run",
                ownershipStrategy: .privateOwned
            )
        )
        let run = fixture.makeRun(definition: definition, status: .running, thread: thread)
        definition.runs = [run]
        thread.scheduledTaskRun = run
        fixture.context.insert(thread)
        fixture.context.insert(run)
        try fixture.context.save()
        let definitionID = definition.id
        let runID = run.id
        let threadID = thread.persistentModelID

        try fixture.service.delete(definitionID: definitionID, expectedRevision: 1)

        XCTAssertNil(fixture.context.resolveScheduledTask(id: definitionID))
        let survivingRun = try XCTUnwrap(fixture.run(id: runID))
        XCTAssertNil(survivingRun.scheduledTask)
        XCTAssertEqual(survivingRun.definitionID, definitionID)
        XCTAssertEqual(survivingRun.status, .running)
        XCTAssertEqual(survivingRun.thread?.persistentModelID, threadID)
        XCTAssertNotNil(fixture.context.resolveThread(id: threadID))
    }

    func testRevisionConflictRejectsStaleEditWithoutChangingDefinition() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let definition = try fixture.insertDefinition(revision: 3)

        XCTAssertThrowsError(
            try fixture.service.pause(
                definitionID: definition.id,
                expectedRevision: 2
            )
        ) { error in
            XCTAssertEqual(
                error as? ScheduledTaskMutationError,
                .revisionConflict(expected: 2, actual: 3)
            )
        }
        XCTAssertEqual(definition.state, .active)
        XCTAssertEqual(definition.revision, 3)
    }
}

@MainActor
private struct ScheduledTaskMutationFixture {
    let container: ModelContainer
    let context: ModelContext
    let service: ScheduledTaskMutationService

    init() throws {
        container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        service = ScheduledTaskMutationService(modelContext: context)
    }

    func insertDefinition(
        id: String = UUID().uuidString,
        revision: Int = 1,
        state: ScheduledTaskState = .active,
        recurrence: ScheduledTaskRecurrence = .daily(hour: 8, minute: 0),
        nextOccurrenceAt: Date? = nil,
        pendingOccurrenceAt: Date? = nil,
        pauseReason: String? = nil,
        lastError: String? = nil
    ) throws -> ScheduledTask {
        let definition = ScheduledTask(
            id: id,
            title: "Original",
            prompt: "Original prompt",
            revision: revision,
            state: state,
            recurrence: recurrence,
            timeZoneIdentifier: "UTC",
            providerID: "codex",
            nextOccurrenceAt: nextOccurrenceAt,
            pendingOccurrenceAt: pendingOccurrenceAt,
            pauseReason: pauseReason,
            lastError: lastError
        )
        context.insert(definition)
        try context.save()
        return definition
    }

    func makeRun(
        definition: ScheduledTask,
        status: ScheduledTaskRunStatus,
        thread: AgentThread? = nil
    ) -> ScheduledTaskRun {
        ScheduledTaskRun(
            occurrenceID: UUID().uuidString,
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: Date(timeIntervalSince1970: 100),
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
            scheduledTask: definition,
            thread: thread
        )
    }

    func run(id: String) -> ScheduledTaskRun? {
        let descriptor = FetchDescriptor<ScheduledTaskRun>(
            predicate: #Predicate { run in
                run.id == id
            }
        )
        return try? context.fetch(descriptor).first
    }
}
