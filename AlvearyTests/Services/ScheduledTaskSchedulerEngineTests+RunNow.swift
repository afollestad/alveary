import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskSchedulerEngineTests {
    func testRunNowPausesDefinitionWithUnknownPersistedStateBeforePreflight() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let definition = try fixture.insertDefinition(nextOccurrenceAt: fixture.date(900))
        definition.stateRawValue = "future-state"
        try fixture.context.save()
        let request = ScheduledTaskRunNowRequest(
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: fixture.date(600),
            triggeredAt: fixture.date(600),
            occurrenceSource: .manual
        )
        var didRunPreflight = false
        let engine = fixture.makeEngine { snapshot in
            didRunPreflight = true
            return scheduledTaskReadyOutcome(for: snapshot)
        }

        let result = try await engine.claimRunNow(request)

        guard case let .paused(reason) = result else {
            return XCTFail("Expected malformed definition state to pause Run now")
        }
        XCTAssertEqual(reason, "Scheduled task state is invalid.")
        XCTAssertEqual(definition.state, .paused)
        XCTAssertFalse(didRunPreflight)
        XCTAssertEqual(try fixture.runCount(), 0)
    }

    func testRunNowPausesAnActiveDefinitionWithNoPersistedOccurrence() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let definition = try fixture.insertDefinition(nextOccurrenceAt: nil)
        let request = ScheduledTaskRunNowRequest(
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: fixture.date(600),
            triggeredAt: fixture.date(600),
            occurrenceSource: .manual
        )

        let result = try await fixture.makeEngine().claimRunNow(request)

        guard case let .paused(reason) = result else {
            return XCTFail("Expected missing occurrence state to pause")
        }
        XCTAssertEqual(reason, "Scheduled task next occurrence is missing.")
        XCTAssertEqual(definition.state, .paused)
        XCTAssertEqual(definition.nextOccurrenceAt, fixture.date(28_800))
        XCTAssertEqual(definition.revision, 2)
        XCTAssertEqual(try fixture.runCount(), 0)
    }

    func testManualRunNowLeavesCompletedDefinitionCadenceAndStateUnchanged() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let occurrence = fixture.date(300)
        let definition = try fixture.insertDefinition(
            state: .completed,
            recurrence: .once(occurrence),
            nextOccurrenceAt: nil
        )
        let request = ScheduledTaskRunNowRequest(
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: fixture.date(600),
            triggeredAt: fixture.date(600),
            occurrenceSource: .manual
        )

        let result = try await fixture.makeEngine().claimRunNow(request)

        guard case let .claimed(runID) = result else {
            return XCTFail("Expected manual Run now to be claimed")
        }
        let run = try XCTUnwrap(fixture.run(id: runID))
        XCTAssertEqual(run.triggerKind, .runNow)
        XCTAssertEqual(run.occurrenceAt, fixture.date(600))
        XCTAssertEqual(definition.state, .completed)
        XCTAssertNil(definition.nextOccurrenceAt)
    }

    func testManualRunNowIdempotencyKeyReusesClaimAcrossDifferentConfirmationTimes() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let definition = try fixture.insertDefinition(
            state: .completed,
            recurrence: .once(fixture.date(300)),
            nextOccurrenceAt: nil
        )
        let firstRequest = ScheduledTaskRunNowRequest(
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: fixture.date(600),
            triggeredAt: fixture.date(600),
            occurrenceSource: .manual,
            idempotencyKey: "proposal-1"
        )
        let engine = fixture.makeEngine()

        let firstResult = try await engine.claimRunNow(firstRequest)
        guard case let .claimed(runID) = firstResult,
              let run = fixture.run(id: runID) else {
            return XCTFail("Expected first Run now request to be claimed; received \(String(describing: firstResult))")
        }
        run.status = .success
        run.finishedAt = fixture.date(700)
        try fixture.context.save()

        let retryRequest = ScheduledTaskRunNowRequest(
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: fixture.date(900),
            triggeredAt: fixture.date(900),
            occurrenceSource: .manual,
            idempotencyKey: "proposal-1"
        )
        guard case let .alreadyClaimed(retriedRunID) = try await engine.claimRunNow(retryRequest) else {
            return XCTFail("Expected retry to resolve the existing run")
        }

        XCTAssertEqual(retriedRunID, run.persistentModelID)
        XCTAssertEqual(try fixture.runCount(), 1)
    }

    func testScheduledRunNowIdempotencyKeyReusesClaimAfterCadenceAdvances() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let definition = try fixture.insertDefinition(
            recurrence: .interval(minutes: 5, anchor: fixture.date(0)),
            nextOccurrenceAt: fixture.date(300)
        )
        let firstRequest = ScheduledTaskRunNowRequest(
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: fixture.date(600),
            triggeredAt: fixture.date(600),
            occurrenceSource: .scheduled,
            idempotencyKey: "scheduled-proposal"
        )
        var preflightCount = 0
        let engine = fixture.makeEngine { snapshot in
            preflightCount += 1
            guard preflightCount == 1 else {
                return .invalid(reason: "Provider became unavailable.")
            }
            return scheduledTaskReadyOutcome(for: snapshot)
        }

        let firstResult = try await engine.claimRunNow(firstRequest)
        guard case let .claimed(runID) = firstResult,
              let run = fixture.run(id: runID) else {
            return XCTFail("Expected the scheduled occurrence to be claimed")
        }
        run.status = .success
        run.finishedAt = fixture.date(650)
        try fixture.context.save()

        let retryRequest = ScheduledTaskRunNowRequest(
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: fixture.date(900),
            triggeredAt: fixture.date(900),
            occurrenceSource: .scheduled,
            idempotencyKey: "scheduled-proposal"
        )
        guard case let .alreadyClaimed(retriedRunID) = try await engine.claimRunNow(retryRequest) else {
            return XCTFail("Expected the retry to reuse the consumed scheduled occurrence")
        }

        XCTAssertEqual(retriedRunID, run.persistentModelID)
        XCTAssertEqual(preflightCount, 1)
        XCTAssertEqual(definition.state, .active)
        XCTAssertEqual(definition.revision, 1)
        XCTAssertEqual(definition.nextOccurrenceAt, fixture.date(900))
        XCTAssertNil(definition.lastError)
        XCTAssertEqual(try fixture.runCount(), 1)
    }

    func testPendingRunNowIdempotencyKeyReusesClaimAfterPendingOccurrenceClears() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let definition = try fixture.insertDefinition(
            state: .paused,
            recurrence: .interval(minutes: 5, anchor: fixture.date(0)),
            nextOccurrenceAt: fixture.date(900),
            pendingOccurrenceAt: fixture.date(540)
        )
        let firstRequest = ScheduledTaskRunNowRequest(
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: fixture.date(540),
            triggeredAt: fixture.date(600),
            occurrenceSource: .pending,
            idempotencyKey: "pending-proposal"
        )
        let engine = fixture.makeEngine()

        let firstResult = try await engine.claimRunNow(firstRequest)
        guard case let .claimed(runID) = firstResult,
              let run = fixture.run(id: runID) else {
            return XCTFail("Expected the pending occurrence to be claimed")
        }
        run.status = .success
        run.finishedAt = fixture.date(650)
        try fixture.context.save()

        let retryRequest = ScheduledTaskRunNowRequest(
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: fixture.date(900),
            triggeredAt: fixture.date(900),
            occurrenceSource: .scheduled,
            idempotencyKey: "pending-proposal"
        )
        guard case let .alreadyClaimed(retriedRunID) = try await engine.claimRunNow(retryRequest) else {
            return XCTFail("Expected the retry to reuse the consumed pending occurrence")
        }

        XCTAssertEqual(retriedRunID, run.persistentModelID)
        XCTAssertNil(definition.pendingOccurrenceAt)
        XCTAssertEqual(definition.nextOccurrenceAt, fixture.date(900))
        XCTAssertEqual(try fixture.runCount(), 1)
    }

    func testRunNowConsumesLatestDueOccurrenceAndAdvancesAnchoredCadencePastTriggerTime() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let definition = try fixture.insertDefinition(
            recurrence: .interval(minutes: 5, anchor: fixture.date(0)),
            nextOccurrenceAt: fixture.date(300)
        )
        let request = ScheduledTaskRunNowRequest(
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: fixture.date(600),
            triggeredAt: fixture.date(600),
            occurrenceSource: .scheduled
        )

        let result = try await fixture.makeEngine().claimRunNow(request)

        guard case let .claimed(runID) = result else {
            return XCTFail("Expected due Run now to be claimed")
        }
        let run = try XCTUnwrap(fixture.run(id: runID))
        XCTAssertEqual(run.triggerKind, .runNow)
        XCTAssertEqual(run.occurrenceAt, fixture.date(600))
        XCTAssertEqual(definition.state, .active)
        XCTAssertEqual(definition.nextOccurrenceAt, fixture.date(900))
    }

    func testRunNowRejectsARequestForAnOlderMissedOccurrence() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let definition = try fixture.insertDefinition(
            recurrence: .interval(minutes: 5, anchor: fixture.date(0)),
            nextOccurrenceAt: fixture.date(300)
        )
        let request = ScheduledTaskRunNowRequest(
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: fixture.date(300),
            triggeredAt: fixture.date(600),
            occurrenceSource: .scheduled
        )

        let result = try await fixture.makeEngine().claimRunNow(request)

        guard case .changedDuringPreflight = result else {
            return XCTFail("Expected stale missed occurrence provenance to be rejected")
        }
        XCTAssertEqual(definition.nextOccurrenceAt, fixture.date(300))
        XCTAssertEqual(try fixture.runCount(), 0)
    }

    func testRunNowConsumesLatestCalendarOccurrenceWithoutShiftingWallClockCadence() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let definition = try fixture.insertDefinition(
            recurrence: .daily(hour: 8, minute: 0),
            nextOccurrenceAt: fixture.date(28_800)
        )
        let request = ScheduledTaskRunNowRequest(
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: fixture.date(201_600),
            triggeredAt: fixture.date(205_200),
            occurrenceSource: .scheduled
        )

        let result = try await fixture.makeEngine().claimRunNow(request)

        guard case let .claimed(runID) = result else {
            return XCTFail("Expected the latest daily occurrence to be claimed")
        }
        XCTAssertEqual(fixture.run(id: runID)?.occurrenceAt, fixture.date(201_600))
        XCTAssertEqual(definition.nextOccurrenceAt, fixture.date(288_000))
    }

    func testRunNowConsumesPendingOccurrenceWithoutResumingPausedDefinition() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let definition = try fixture.insertDefinition(
            state: .paused,
            recurrence: .interval(minutes: 5, anchor: fixture.date(0)),
            nextOccurrenceAt: fixture.date(900),
            pendingOccurrenceAt: fixture.date(540)
        )
        let request = ScheduledTaskRunNowRequest(
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: fixture.date(540),
            triggeredAt: fixture.date(600),
            occurrenceSource: .pending
        )

        let result = try await fixture.makeEngine().claimRunNow(request)

        guard case .claimed = result else {
            return XCTFail("Expected pending Run now to be claimed")
        }
        XCTAssertEqual(definition.state, .paused)
        XCTAssertNil(definition.pendingOccurrenceAt)
        XCTAssertEqual(definition.nextOccurrenceAt, fixture.date(900))
    }

    func testRunNowConsumingLatestScheduledOccurrenceClearsOlderPendingOverlap() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let definition = try fixture.insertDefinition(
            recurrence: .interval(minutes: 5, anchor: fixture.date(0)),
            nextOccurrenceAt: fixture.date(600),
            pendingOccurrenceAt: fixture.date(300)
        )
        let request = ScheduledTaskRunNowRequest(
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: fixture.date(600),
            triggeredAt: fixture.date(600),
            occurrenceSource: .scheduled
        )

        let result = try await fixture.makeEngine().claimRunNow(request)

        guard case .claimed = result else {
            return XCTFail("Expected scheduled Run now to be claimed")
        }
        XCTAssertNil(definition.pendingOccurrenceAt)
        XCTAssertEqual(definition.nextOccurrenceAt, fixture.date(900))
    }
}
