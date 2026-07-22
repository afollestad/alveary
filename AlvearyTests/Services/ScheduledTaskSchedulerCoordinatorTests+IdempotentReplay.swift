import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskSchedulerCoordinatorTests {
    func testRunNowReplayDoesNotReplaceActiveLaunchOwnership() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definition = try fixture.insertDefinition(id: "run-now-replay", projectPath: "/tmp/run-now-replay")
        let executionProbe = ScheduledTaskBlockingProbe()
        let services = fixture.makeServices(executionProbe: executionProbe)
        let request = ScheduledTaskRunNowRequest.prepare(
            definition: definition,
            triggeredAt: fixture.actionDate,
            recurrenceCalculator: ScheduledTaskRecurrenceCalculator(),
            idempotencyKey: "same-request"
        )

        XCTAssertTrue(services.coordinator.startRunNow(request))
        try await waitUntil("expected original Run now execution") {
            await executionProbe.snapshot().entryCount == 1
        }
        let run = try XCTUnwrap(fixture.runs().first)
        let originalLaunchID = try XCTUnwrap(services.coordinator.launchIDsByRunID[run.persistentModelID])

        XCTAssertTrue(services.coordinator.startRunNow(request))
        try await waitUntil("expected idempotent replay claim to finish") {
            services.coordinator.definitionIDsBeingClaimed.isEmpty
        }

        XCTAssertEqual(services.coordinator.launchIDsByRunID[run.persistentModelID], originalLaunchID)
        let replaySnapshot = await executionProbe.snapshot()
        XCTAssertEqual(replaySnapshot.entryCount, 1)

        await executionProbe.release()
        await services.coordinator.waitUntilIdle()
        XCTAssertEqual(run.status, .success)
    }
}
