import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskSchedulerEngineTests {
    func testScheduledClaimSaveFailureRestoresOneShotCadenceAndRemovesInsertedRun() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let occurrence = fixture.date(300)
        let pendingOccurrence = fixture.date(240)
        let definition = try fixture.insertDefinition(
            recurrence: .once(occurrence),
            nextOccurrenceAt: occurrence,
            pendingOccurrenceAt: pendingOccurrence
        )
        let unrelatedProject = try insertUnrelatedProject(in: fixture)
        let engine = fixture.makeEngine(
            preflight: { snapshot in
                unrelatedProject.name = "Pending unrelated edit"
                return scheduledTaskReadyOutcome(for: snapshot)
            },
            saveState: { _ in
                throw ScheduledTaskClaimPersistenceTestError.saveFailed
            }
        )

        do {
            _ = try await engine.claimDue(
                definitionID: definition.id,
                at: fixture.date(301)
            )
            XCTFail("Expected claim persistence to fail")
        } catch ScheduledTaskClaimPersistenceTestError.saveFailed {
            // Expected.
        }

        XCTAssertEqual(definition.state, .active)
        XCTAssertEqual(definition.nextOccurrenceAt, occurrence)
        XCTAssertEqual(definition.pendingOccurrenceAt, pendingOccurrence)
        XCTAssertEqual(unrelatedProject.name, "Pending unrelated edit")
        XCTAssertEqual(try fixture.runCount(), 0)

        try fixture.context.save()
        try assertPersistedClaimRollback(
            fixture: fixture,
            definitionID: definition.id,
            expectedState: .active,
            expectedNextOccurrenceAt: occurrence,
            expectedPendingOccurrenceAt: pendingOccurrence
        )
    }

    func testInvalidDefinitionPauseSaveFailureRestoresFieldsAndCanRetry() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let occurrence = fixture.date(300)
        let pendingOccurrence = fixture.date(240)
        let originalModifiedAt = fixture.date(100)
        let actionDate = fixture.date(301)
        let definition = try fixture.insertDefinition(
            nextOccurrenceAt: occurrence,
            pendingOccurrenceAt: pendingOccurrence
        )
        try configureOriginalPauseFields(
            definition,
            modifiedAt: originalModifiedAt,
            context: fixture.context
        )

        let unrelatedProject = try insertUnrelatedProject(in: fixture)
        let invalidReason = "The configured provider is unavailable."
        let saver = ScheduledTaskPauseStateSaver()
        let engine = makeInvalidPauseEngine(
            fixture: fixture,
            unrelatedProject: unrelatedProject,
            invalidReason: invalidReason,
            saver: saver
        )

        try await assertInvalidPauseFailureRestoresState(
            fixture: fixture,
            definition: definition,
            engine: engine,
            saver: saver,
            expectation: ScheduledTaskPauseRestorationExpectation(
                nextOccurrenceAt: occurrence,
                pendingOccurrenceAt: pendingOccurrence,
                modifiedAt: originalModifiedAt,
                actionDate: actionDate
            )
        )

        let retryResult = try await engine.claimDue(
            definitionID: definition.id,
            at: actionDate
        )
        guard case .paused(let retryReason) = retryResult else {
            return XCTFail("Expected retry to persist an invalid-definition pause")
        }
        XCTAssertEqual(retryReason, invalidReason)
        XCTAssertEqual(saver.attempts, 2)
        assertRetriedPauseFields(
            definition,
            reason: invalidReason,
            modifiedAt: actionDate
        )
    }

    func testRunNowClaimSaveFailureRestoresPendingAndAnchoredCadence() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let nextOccurrence = fixture.date(300)
        let pendingOccurrence = fixture.date(540)
        let triggerDate = fixture.date(600)
        let definition = try fixture.insertDefinition(
            recurrence: .interval(minutes: 5, anchor: fixture.date(0)),
            nextOccurrenceAt: nextOccurrence,
            pendingOccurrenceAt: pendingOccurrence
        )
        let request = ScheduledTaskRunNowRequest.prepare(
            definition: definition,
            triggeredAt: triggerDate,
            recurrenceCalculator: ScheduledTaskRecurrenceCalculator()
        )
        let engine = fixture.makeEngine(
            saveState: { _ in
                throw ScheduledTaskClaimPersistenceTestError.saveFailed
            }
        )

        do {
            _ = try await engine.claimRunNow(request)
            XCTFail("Expected Run now claim persistence to fail")
        } catch ScheduledTaskClaimPersistenceTestError.saveFailed {
            // Expected.
        }

        XCTAssertEqual(definition.state, .active)
        XCTAssertEqual(definition.nextOccurrenceAt, nextOccurrence)
        XCTAssertEqual(definition.pendingOccurrenceAt, pendingOccurrence)
        XCTAssertEqual(try fixture.runCount(), 0)

        try fixture.context.save()
        try assertPersistedClaimRollback(
            fixture: fixture,
            definitionID: definition.id,
            expectedState: .active,
            expectedNextOccurrenceAt: nextOccurrence,
            expectedPendingOccurrenceAt: pendingOccurrence
        )
    }
}

@MainActor
private extension ScheduledTaskSchedulerEngineTests {
    func makeInvalidPauseEngine(
        fixture: ScheduledTaskSchedulerFixture,
        unrelatedProject: Project,
        invalidReason: String,
        saver: ScheduledTaskPauseStateSaver
    ) -> ScheduledTaskSchedulerEngine {
        fixture.makeEngine(
            preflight: { _ in
                unrelatedProject.name = "Pending unrelated edit"
                return .invalid(reason: invalidReason)
            },
            saveState: saver.save
        )
    }

    func assertInvalidPauseFailureRestoresState(
        fixture: ScheduledTaskSchedulerFixture,
        definition: ScheduledTask,
        engine: ScheduledTaskSchedulerEngine,
        saver: ScheduledTaskPauseStateSaver,
        expectation: ScheduledTaskPauseRestorationExpectation
    ) async throws {
        do {
            _ = try await engine.claimDue(definitionID: definition.id, at: expectation.actionDate)
            XCTFail("Expected invalid-definition pause persistence to fail")
        } catch ScheduledTaskClaimPersistenceTestError.saveFailed {
            // Expected.
        }

        XCTAssertEqual(saver.attempts, 1)
        assertOriginalPauseFields(
            definition,
            nextOccurrenceAt: expectation.nextOccurrenceAt,
            pendingOccurrenceAt: expectation.pendingOccurrenceAt,
            modifiedAt: expectation.modifiedAt
        )
        XCTAssertEqual(
            try fixture.context.fetch(FetchDescriptor<Project>()).first?.name,
            "Pending unrelated edit"
        )
        try fixture.context.save()
        try assertPersistedPauseRestoration(
            fixture: fixture,
            definitionID: definition.id,
            nextOccurrenceAt: expectation.nextOccurrenceAt,
            pendingOccurrenceAt: expectation.pendingOccurrenceAt,
            modifiedAt: expectation.modifiedAt
        )
    }

    func configureOriginalPauseFields(
        _ definition: ScheduledTask,
        modifiedAt: Date,
        context: ModelContext
    ) throws {
        definition.pauseReason = "Original pause reason"
        definition.lastError = "Original error"
        definition.revision = 7
        definition.modifiedAt = modifiedAt
        try context.save()
    }

    func assertOriginalPauseFields(
        _ definition: ScheduledTask,
        nextOccurrenceAt: Date,
        pendingOccurrenceAt: Date,
        modifiedAt: Date
    ) {
        XCTAssertEqual(definition.state, .active)
        XCTAssertEqual(definition.nextOccurrenceAt, nextOccurrenceAt)
        XCTAssertEqual(definition.pendingOccurrenceAt, pendingOccurrenceAt)
        XCTAssertEqual(definition.pauseReason, "Original pause reason")
        XCTAssertEqual(definition.lastError, "Original error")
        XCTAssertEqual(definition.revision, 7)
        XCTAssertEqual(definition.modifiedAt, modifiedAt)
    }

    func assertPersistedPauseRestoration(
        fixture: ScheduledTaskSchedulerFixture,
        definitionID: String,
        nextOccurrenceAt: Date,
        pendingOccurrenceAt: Date,
        modifiedAt: Date
    ) throws {
        let context = ModelContext(fixture.container)
        let definition = try XCTUnwrap(context.resolveScheduledTask(id: definitionID))
        assertOriginalPauseFields(
            definition,
            nextOccurrenceAt: nextOccurrenceAt,
            pendingOccurrenceAt: pendingOccurrenceAt,
            modifiedAt: modifiedAt
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<Project>()).first?.name,
            "Pending unrelated edit"
        )
    }

    func assertRetriedPauseFields(
        _ definition: ScheduledTask,
        reason: String,
        modifiedAt: Date
    ) {
        XCTAssertEqual(definition.state, .paused)
        XCTAssertNil(definition.pendingOccurrenceAt)
        XCTAssertEqual(definition.pauseReason, reason)
        XCTAssertEqual(definition.lastError, reason)
        XCTAssertEqual(definition.revision, 8)
        XCTAssertEqual(definition.modifiedAt, modifiedAt)
    }

    func insertUnrelatedProject(
        in fixture: ScheduledTaskSchedulerFixture
    ) throws -> Project {
        let project = Project(
            path: "/tmp/scheduled-claim-save-unrelated",
            name: "Original unrelated name"
        )
        fixture.context.insert(project)
        try fixture.context.save()
        return project
    }

    func assertPersistedClaimRollback(
        fixture: ScheduledTaskSchedulerFixture,
        definitionID: String,
        expectedState: ScheduledTaskState,
        expectedNextOccurrenceAt: Date?,
        expectedPendingOccurrenceAt: Date?
    ) throws {
        let verificationContext = ModelContext(fixture.container)
        let persistedDefinition = try XCTUnwrap(
            verificationContext.resolveScheduledTask(id: definitionID)
        )
        XCTAssertEqual(persistedDefinition.state, expectedState)
        XCTAssertEqual(persistedDefinition.nextOccurrenceAt, expectedNextOccurrenceAt)
        XCTAssertEqual(persistedDefinition.pendingOccurrenceAt, expectedPendingOccurrenceAt)
        XCTAssertEqual(
            try verificationContext.fetchCount(FetchDescriptor<ScheduledTaskRun>()),
            0
        )
    }
}

private enum ScheduledTaskClaimPersistenceTestError: Error {
    case saveFailed
}

private struct ScheduledTaskPauseRestorationExpectation {
    let nextOccurrenceAt: Date
    let pendingOccurrenceAt: Date
    let modifiedAt: Date
    let actionDate: Date
}

@MainActor
private final class ScheduledTaskPauseStateSaver {
    private(set) var attempts = 0

    func save(_ context: ModelContext) throws {
        attempts += 1
        if attempts == 1 {
            throw ScheduledTaskClaimPersistenceTestError.saveFailed
        }
        try context.save()
    }
}
