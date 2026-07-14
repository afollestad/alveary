import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskSchedulerEngineTests {
    func testInvalidDefinitionStatePausesBeforePreflightWithoutClaiming() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let definition = try fixture.insertDefinition(nextOccurrenceAt: fixture.date(300))
        definition.stateRawValue = "future-state"
        try fixture.context.save()
        var didRunPreflight = false
        let engine = fixture.makeEngine { snapshot in
            didRunPreflight = true
            return scheduledTaskReadyOutcome(for: snapshot)
        }

        let result = try await engine.claimDue(
            definitionID: definition.id,
            at: fixture.date(301)
        )

        guard case let .paused(reason) = result else {
            return XCTFail("Expected malformed definition state to pause")
        }
        XCTAssertEqual(reason, "Scheduled task state is invalid.")
        XCTAssertEqual(definition.state, .paused)
        XCTAssertFalse(didRunPreflight)
        XCTAssertEqual(try fixture.runCount(), 0)
    }

    func testUnknownRunStatusBlocksDueClaimBeforePreflight() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let definition = try fixture.insertDefinition(
            recurrence: .interval(minutes: 5, anchor: fixture.date(0)),
            nextOccurrenceAt: fixture.date(300)
        )
        let run = try fixture.insertRun(
            definition: definition,
            status: .success,
            occurrenceAt: fixture.date(0)
        )
        run.statusRawValue = "future-status"
        try fixture.context.save()
        var didRunPreflight = false
        let engine = fixture.makeEngine { snapshot in
            didRunPreflight = true
            return scheduledTaskReadyOutcome(for: snapshot)
        }

        let result = try await engine.claimDue(
            definitionID: definition.id,
            at: fixture.date(1_000)
        )

        guard case let .overlapped(pendingOccurrenceAt) = result else {
            return XCTFail("Expected unknown run status to block a new claim")
        }
        XCTAssertEqual(pendingOccurrenceAt, fixture.date(900))
        XCTAssertFalse(didRunPreflight)
        XCTAssertEqual(definition.pendingOccurrenceAt, fixture.date(900))
        XCTAssertEqual(definition.nextOccurrenceAt, fixture.date(1_200))
        XCTAssertEqual(try fixture.runCount(), 1)
    }

    func testInvalidWorkspaceKindPausesBeforePreflightWithoutClaiming() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let definition = try fixture.insertDefinition(nextOccurrenceAt: fixture.date(300))
        definition.workspaceKindRawValue = "future-workspace-kind"
        try fixture.context.save()
        var didRunPreflight = false
        let engine = fixture.makeEngine { snapshot in
            didRunPreflight = true
            return scheduledTaskReadyOutcome(for: snapshot)
        }

        let result = try await engine.claimDue(
            definitionID: definition.id,
            at: fixture.date(301)
        )

        guard case let .paused(reason) = result else {
            return XCTFail("Expected malformed workspace kind to pause")
        }
        XCTAssertEqual(reason, "Scheduled task workspace kind is invalid.")
        XCTAssertEqual(definition.state, .paused)
        XCTAssertFalse(didRunPreflight)
        XCTAssertEqual(try fixture.runCount(), 0)
    }

    func testInvalidWorkspaceStrategyPausesBeforePreflightWithoutClaiming() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let definition = try fixture.insertDefinition(nextOccurrenceAt: fixture.date(300))
        definition.workspaceStrategyRawValue = "future-workspace-strategy"
        try fixture.context.save()
        var didRunPreflight = false
        let engine = fixture.makeEngine { snapshot in
            didRunPreflight = true
            return scheduledTaskReadyOutcome(for: snapshot)
        }

        let result = try await engine.claimDue(
            definitionID: definition.id,
            at: fixture.date(301)
        )

        guard case let .paused(reason) = result else {
            return XCTFail("Expected malformed workspace strategy to pause")
        }
        XCTAssertEqual(reason, "Scheduled task workspace strategy is invalid.")
        XCTAssertEqual(definition.state, .paused)
        XCTAssertFalse(didRunPreflight)
        XCTAssertEqual(try fixture.runCount(), 0)
    }
}
