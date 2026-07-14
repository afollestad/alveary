import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskRunRecoveryCoordinatorTests {
    func testRecoveryAgesRunNowClaimFromFreshTriggerInsteadOfStaleOccurrence() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let now = Date(timeIntervalSinceReferenceDate: 1_500_000)
        let staleOccurrence = now.addingTimeInterval(
            -(ScheduledTaskRecurrenceCalculator.defaultCatchUpAge + 1)
        )
        let runNow = fixture.insertRun(
            status: .claimed,
            occurrenceAt: staleOccurrence,
            withThread: false
        )
        runNow.triggerKind = .runNow
        runNow.triggeredAt = now.addingTimeInterval(-30)
        let scheduled = fixture.insertRun(
            status: .claimed,
            occurrenceAt: staleOccurrence,
            withThread: false
        )
        scheduled.triggeredAt = now.addingTimeInterval(-30)
        try fixture.context.save()

        let result = try fixture.coordinator.recoverPersistedRuns(at: now) { _ in true }

        XCTAssertEqual(Set(result.resumedRunIDs), Set([runNow.persistentModelID]))
        XCTAssertEqual(Set(result.interruptedRunIDs), Set([scheduled.persistentModelID]))
        XCTAssertEqual(runNow.status, .claimed)
        XCTAssertEqual(scheduled.status, .interrupted)
    }

    func testRecoveryInterruptsClaimWithUnknownTriggerKind() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let now = Date(timeIntervalSinceReferenceDate: 1_600_000)
        let run = fixture.insertRun(
            status: .claimed,
            occurrenceAt: now.addingTimeInterval(-30),
            withThread: false
        )
        run.triggerKindRawValue = "future-trigger"
        try fixture.context.save()

        let result = try fixture.coordinator.recoverPersistedRuns(at: now) { _ in true }

        XCTAssertTrue(result.resumedRunIDs.isEmpty)
        XCTAssertEqual(result.interruptedRunIDs, [run.persistentModelID])
        XCTAssertEqual(run.status, .interrupted)
    }

    func testRecoveryInterruptsRunWithUnknownStatusWithoutEvaluatingResumeSafety() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let now = Date(timeIntervalSinceReferenceDate: 1_700_000)
        let run = fixture.insertRun(
            status: .claimed,
            occurrenceAt: now.addingTimeInterval(-30),
            withThread: false
        )
        run.statusRawValue = "future-status"
        try fixture.context.save()
        var didEvaluateResumeSafety = false

        let result = try fixture.coordinator.recoverPersistedRuns(at: now) { _ in
            didEvaluateResumeSafety = true
            return true
        }

        XCTAssertFalse(didEvaluateResumeSafety)
        XCTAssertTrue(result.resumedRunIDs.isEmpty)
        XCTAssertEqual(result.interruptedRunIDs, [run.persistentModelID])
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertEqual(run.finishedAt, now)
        XCTAssertEqual(run.lastError, "The scheduled task run has an invalid persisted status.")
    }

    func testTerminationInterruptsRunWithUnknownStatus() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let now = Date(timeIntervalSinceReferenceDate: 1_800_000)
        let run = fixture.insertRun(status: .success, occurrenceAt: now.addingTimeInterval(-30))
        run.statusRawValue = "future-status"
        try fixture.context.save()

        let result = try fixture.coordinator.prepareForTermination(at: now)

        XCTAssertEqual(result.interruptedRunIDs, [run.persistentModelID])
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertEqual(run.finishedAt, now)
    }
}
