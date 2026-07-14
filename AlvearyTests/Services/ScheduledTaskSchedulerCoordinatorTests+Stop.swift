import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskSchedulerCoordinatorTests {
    func testStopAndWaitReturnsImmediatelyForHistoricalRun() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definition = try fixture.insertDefinition(id: "stale-stop", projectPath: "/tmp/stale-stop")
        let run = try fixture.insertRun(definition: definition, status: .success)
        definition.pendingOccurrenceAt = fixture.actionDate
        try fixture.context.save()
        let services = fixture.makeServices()

        try await services.coordinator.stopAndWait(runID: run.persistentModelID)

        XCTAssertEqual(definition.pendingOccurrenceAt, fixture.actionDate)
        XCTAssertTrue(services.executor.stopRunIDs.isEmpty)
    }

    func testStopAndWaitOnlyWaitsForTrackedTerminalRun() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definition = try fixture.insertDefinition(id: "terminal-wait", projectPath: "/tmp/terminal-wait")
        let executionProbe = ScheduledTaskBlockingProbe()
        let completionProbe = ScheduledTaskBlockingProbe()
        let services = fixture.makeServices(executionProbe: executionProbe)
        var waitTask: Task<Void, Error>?

        do {
            XCTAssertTrue(services.coordinator.startDueTask(definitionID: definition.id, at: fixture.actionDate))
            try await waitUntil("expected execution before terminal wait") {
                await executionProbe.snapshot().entryCount == 1
            }
            let run = try XCTUnwrap(fixture.runs().first)
            let pendingOccurrenceAt = fixture.actionDate.addingTimeInterval(3_600)
            run.status = .success
            run.finishedAt = fixture.actionDate
            definition.pendingOccurrenceAt = pendingOccurrenceAt
            try fixture.context.save()

            let wait = Task { @MainActor in
                try await services.coordinator.stopAndWait(runID: run.persistentModelID)
                await completionProbe.enter("wait-complete")
            }
            waitTask = wait
            for _ in 0 ..< 20 {
                await Task.yield()
            }

            XCTAssertTrue(services.coordinator.isActive(runID: run.persistentModelID))
            let completionSnapshot = await completionProbe.snapshot()
            XCTAssertEqual(completionSnapshot.entryCount, 0)
            XCTAssertTrue(services.executor.stopRunIDs.isEmpty)
            XCTAssertEqual(definition.pendingOccurrenceAt, pendingOccurrenceAt)

            await executionProbe.release()
            try await waitUntil("expected wait-only quiescence after launch finalization") {
                await completionProbe.snapshot().entryCount == 1
            }
            XCTAssertTrue(services.executor.stopRunIDs.isEmpty)
            XCTAssertEqual(definition.pendingOccurrenceAt, pendingOccurrenceAt)

            await completionProbe.release()
            try await wait.value
        } catch {
            await cleanUpBlockedStopTest(
                coordinator: services.coordinator,
                probes: [executionProbe, completionProbe],
                stopTask: waitTask
            )
            throw error
        }
    }

    // swiftlint:disable:next function_body_length
    func testPendingSaveFailureRetriesUntilStoppedOccurrenceIsDurablyCleared() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definition = try fixture.insertDefinition(id: "save-failure", projectPath: "/tmp/save-failure")
        let executionProbe = ScheduledTaskBlockingProbe()
        let retryProbe = ScheduledTaskBlockingProbe()
        var clearAttempts = 0
        let services = fixture.makeServices(
            executionProbe: executionProbe,
            clearPendingOccurrence: { _ in
                clearAttempts += 1
                if clearAttempts == 1 {
                    throw ScheduledTaskCoordinatorTestError.pendingSave
                }
                definition.pendingOccurrenceAt = nil
                try fixture.context.save()
            },
            persistenceRetryWait: {
                await retryProbe.enter("pending-clear")
            }
        )
        var stopTask: Task<Void, Error>?

        do {
            XCTAssertTrue(services.coordinator.startDueTask(definitionID: definition.id, at: fixture.actionDate))
            try await waitUntil("expected execution before failing stop save") {
                await executionProbe.snapshot().entryCount == 1
            }
            let run = try XCTUnwrap(fixture.runs().first)
            let powerSource = KeepAwakeActivitySource.scheduledTaskRun(runID: run.id)
            definition.pendingOccurrenceAt = fixture.actionDate
            try fixture.context.save()

            let stop = Task { @MainActor in
                try await services.coordinator.stopAndWait(runID: run.persistentModelID)
            }
            stopTask = stop
            try await waitUntil("expected pending-clear persistence retry") {
                await retryProbe.snapshot().entryCount == 1
            }

            XCTAssertEqual(services.executor.stopRunIDs, [run.persistentModelID])
            XCTAssertTrue(services.keepAwakeService.isActive(powerSource))
            XCTAssertFalse(services.coordinator.startDueTask(definitionID: definition.id, at: fixture.actionDate))

            await retryProbe.release()
            try await stop.value

            XCTAssertEqual(run.status, .interrupted)
            XCTAssertNil(definition.pendingOccurrenceAt)
            XCTAssertEqual(clearAttempts, 2)
            XCTAssertTrue(services.coordinator.activeRunIDs.isEmpty)
            XCTAssertTrue(services.keepAwakeService.activeSources.isEmpty)
        } catch {
            await cleanUpBlockedStopTest(
                coordinator: services.coordinator,
                probes: [executionProbe, retryProbe],
                stopTask: stopTask
            )
            throw error
        }
    }

    func testStopFencesNewSameDefinitionClaimsUntilTheRunQuiesces() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definition = try fixture.insertDefinition(id: "stop-fence", projectPath: "/tmp/stop-fence")
        definition.recurrence = .interval(minutes: 1, anchor: fixture.actionDate)
        definition.nextOccurrenceAt = fixture.actionDate
        try fixture.context.save()
        let executionProbe = ScheduledTaskBlockingProbe()
        let stopProbe = ScheduledTaskBlockingProbe()
        let services = fixture.makeServices(executionProbe: executionProbe, stopProbe: stopProbe)
        var stopTask: Task<Void, Error>?

        do {
            XCTAssertTrue(services.coordinator.startDueTask(definitionID: definition.id, at: fixture.actionDate))
            try await waitUntil("expected execution before fenced stop") {
                await executionProbe.snapshot().entryCount == 1
            }
            let run = try XCTUnwrap(fixture.runs().first)
            definition.pendingOccurrenceAt = fixture.actionDate.addingTimeInterval(60)
            try fixture.context.save()

            let stop = Task { @MainActor in
                try await services.coordinator.stopAndWait(runID: run.persistentModelID)
            }
            stopTask = stop
            try await waitUntil("expected executor stop to block") {
                await stopProbe.snapshot().entryCount == 1
            }

            XCTAssertFalse(services.coordinator.startDueTask(
                definitionID: definition.id,
                at: fixture.actionDate.addingTimeInterval(60)
            ))

            await stopProbe.release()
            try await stop.value

            XCTAssertEqual(run.status, .interrupted)
            XCTAssertNil(definition.pendingOccurrenceAt)
            XCTAssertFalse(services.coordinator.isActive(runID: run.persistentModelID))
            XCTAssertTrue(services.coordinator.activeRunIDs.isEmpty)
        } catch {
            await cleanUpBlockedStopTest(
                coordinator: services.coordinator,
                probes: [executionProbe, stopProbe],
                stopTask: stopTask
            )
            throw error
        }
    }

    func testStopCompletesOneShotWhoseFinalOccurrenceOverlappedManualRunNow() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definition = try fixture.insertDefinition(id: "one-shot-overlap-stop", projectPath: "/tmp/one-shot-overlap-stop")
        let executionProbe = ScheduledTaskBlockingProbe()
        let services = fixture.makeServices(executionProbe: executionProbe)

        do {
            let overlap = try await startManualRunSpanningDueOneShot(
                fixture: fixture,
                definition: definition,
                coordinator: services.coordinator,
                executionProbe: executionProbe
            )

            try await services.coordinator.stopAndWait(runID: overlap.run.persistentModelID)

            XCTAssertEqual(overlap.run.status, .interrupted)
            XCTAssertEqual(definition.state, .completed)
            XCTAssertNil(definition.nextOccurrenceAt)
            XCTAssertNil(definition.pendingOccurrenceAt)
            XCTAssertEqual(try fixture.runs().count, 1)
        } catch {
            await cleanUpBlockedStopTest(
                coordinator: services.coordinator,
                probes: [executionProbe],
                stopTask: nil
            )
            throw error
        }
    }

    // swiftlint:disable:next function_body_length
    func testOneShotCompletionRollsBackWhenStoppedOccurrenceSaveFails() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definition = try fixture.insertDefinition(id: "one-shot-stop-rollback", projectPath: "/tmp/one-shot-stop-rollback")
        let executionProbe = ScheduledTaskBlockingProbe()
        let retryProbe = ScheduledTaskBlockingProbe()
        var saveAttempts = 0
        let services = fixture.makeServices(
            executionProbe: executionProbe,
            savePendingOccurrenceState: {
                saveAttempts += 1
                if saveAttempts == 1 {
                    throw ScheduledTaskCoordinatorTestError.pendingSave
                }
                try fixture.context.save()
            },
            persistenceRetryWait: {
                await retryProbe.enter("pending-clear")
            }
        )
        var stopTask: Task<Void, Error>?

        do {
            let overlap = try await startManualRunSpanningDueOneShot(
                fixture: fixture,
                definition: definition,
                coordinator: services.coordinator,
                executionProbe: executionProbe
            )
            let stop = Task { @MainActor in
                try await services.coordinator.stopAndWait(runID: overlap.run.persistentModelID)
            }
            stopTask = stop
            try await waitUntil("expected stopped one-shot persistence retry") {
                await retryProbe.snapshot().entryCount == 1
            }

            XCTAssertEqual(definition.state, .active)
            XCTAssertNil(definition.nextOccurrenceAt)
            XCTAssertEqual(definition.pendingOccurrenceAt, overlap.occurrenceAt)
            XCTAssertEqual(saveAttempts, 1)

            await retryProbe.release()
            try await stop.value

            XCTAssertEqual(overlap.run.status, .interrupted)
            XCTAssertEqual(definition.state, .completed)
            XCTAssertNil(definition.nextOccurrenceAt)
            XCTAssertNil(definition.pendingOccurrenceAt)
            XCTAssertEqual(saveAttempts, 2)
        } catch {
            await cleanUpBlockedStopTest(
                coordinator: services.coordinator,
                probes: [executionProbe, retryProbe],
                stopTask: stopTask
            )
            throw error
        }
    }

    // swiftlint:disable:next function_body_length
    func testStopCancelsAndQuiescesSameDefinitionPreflight() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definition = try fixture.insertDefinition(id: "preflight-stop", projectPath: "/tmp/preflight-stop")
        let futureOccurrence = fixture.actionDate.addingTimeInterval(3_600)
        definition.recurrence = .once(futureOccurrence)
        definition.nextOccurrenceAt = futureOccurrence
        try fixture.context.save()
        let preflightProbe = ScheduledTaskBlockingProbe()
        let executionProbe = ScheduledTaskBlockingProbe()
        let stopProbe = ScheduledTaskBlockingProbe()
        let stopCompletionProbe = ScheduledTaskBlockingProbe()
        let services = fixture.makeServices(
            executionProbe: executionProbe,
            stopProbe: stopProbe,
            preflightValidator: { snapshot in
                await preflightProbe.enter(snapshot.definitionID)
                return scheduledTaskReadyOutcome(for: snapshot)
            }
        )
        let runNow = manualRunNowRequest(definition: definition, actionDate: fixture.actionDate)
        var stopTask: Task<Void, Error>?

        do {
            XCTAssertTrue(services.coordinator.startRunNow(runNow))
            try await waitUntil("expected Run now preflight to block") {
                await preflightProbe.snapshot().entryCount == 1
            }
            let recoveredRun = try fixture.insertRun(definition: definition, status: .claimed)
            XCTAssertEqual(services.coordinator.resumeClaimedRuns([recoveredRun.persistentModelID]), 1)
            try await waitUntil("expected recovered run execution") {
                await executionProbe.snapshot().entryCount == 1
            }

            let stop = Task { @MainActor in
                try await services.coordinator.stopAndWait(runID: recoveredRun.persistentModelID)
                await stopCompletionProbe.enter("stop-complete")
            }
            stopTask = stop
            try await waitUntil("expected provider stop to block") {
                await stopProbe.snapshot().entryCount == 1
            }
            await stopProbe.release()
            try await waitUntil("expected stopped run to persist before preflight quiesces") {
                recoveredRun.status == .interrupted
            }

            let completionCountBeforePreflightRelease = await stopCompletionProbe.snapshot().entryCount
            XCTAssertEqual(completionCountBeforePreflightRelease, 0)

            await preflightProbe.release()
            try await waitUntil("expected stop after preflight quiesced") {
                await stopCompletionProbe.snapshot().entryCount == 1
            }
            await stopCompletionProbe.release()
            try await stop.value

            XCTAssertEqual(try fixture.runs().map(\.persistentModelID), [recoveredRun.persistentModelID])
            XCTAssertNil(definition.pendingOccurrenceAt)
            XCTAssertTrue(services.coordinator.activeRunIDs.isEmpty)
        } catch {
            await cleanUpBlockedStopTest(
                coordinator: services.coordinator,
                probes: [preflightProbe, executionProbe, stopProbe, stopCompletionProbe],
                stopTask: stopTask
            )
            throw error
        }
    }
}

@MainActor
private func cleanUpBlockedStopTest(
    coordinator: ScheduledTaskSchedulerCoordinator,
    probes: [ScheduledTaskBlockingProbe],
    stopTask: Task<Void, Error>?
) async {
    stopTask?.cancel()
    for probe in probes {
        await probe.releaseAllForTeardown()
    }
    await coordinator.shutdown()
    if let stopTask {
        _ = await stopTask.result
    }
}

@MainActor
private func manualRunNowRequest(
    definition: ScheduledTask,
    actionDate: Date
) -> ScheduledTaskRunNowRequest {
    ScheduledTaskRunNowRequest(
        definitionID: definition.id,
        definitionRevision: definition.revision,
        occurrenceAt: actionDate,
        triggeredAt: actionDate,
        occurrenceSource: .manual
    )
}

@MainActor
private func startManualRunSpanningDueOneShot(
    fixture: ScheduledTaskCoordinatorFixture,
    definition: ScheduledTask,
    coordinator: ScheduledTaskSchedulerCoordinator,
    executionProbe: ScheduledTaskBlockingProbe
) async throws -> (run: ScheduledTaskRun, occurrenceAt: Date) {
    let occurrenceAt = fixture.actionDate.addingTimeInterval(60)
    definition.recurrence = .once(occurrenceAt)
    definition.nextOccurrenceAt = occurrenceAt
    try fixture.context.save()

    XCTAssertTrue(coordinator.startRunNow(
        manualRunNowRequest(definition: definition, actionDate: fixture.actionDate)
    ))
    try await waitUntil("expected manual Run now execution before one-shot occurrence") {
        await executionProbe.snapshot().entryCount == 1
    }
    let run = try XCTUnwrap(fixture.runs().first)

    XCTAssertTrue(coordinator.startDueTask(definitionID: definition.id, at: occurrenceAt))
    try await waitUntil("expected due one-shot occurrence to be coalesced") {
        definition.pendingOccurrenceAt == occurrenceAt
    }
    XCTAssertEqual(definition.state, .active)
    XCTAssertNil(definition.nextOccurrenceAt)
    return (run, occurrenceAt)
}
