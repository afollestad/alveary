import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskSchedulerCoordinatorTests {
    func testPreExecutionFailureRoutesUnreadToTargetAndReconcilesSiblingControllers() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let project = Project(path: "/tmp/pre-execution-target", name: "Target")
        let target = AgentThread(name: "Pinned target", isPinned: true, project: project)
        let main = Conversation(id: "pre-execution-main", provider: "codex", thread: target)
        let sibling = Conversation(id: "pre-execution-sibling", provider: "codex", isMain: false, thread: target)
        target.conversations = [main, sibling]
        project.threads = [target]
        let run = ScheduledTaskRun(
            occurrenceID: "pre-execution-occurrence",
            definitionID: "pre-execution-definition",
            definitionRevision: 1,
            occurrenceAt: fixture.actionDate,
            triggerKind: .scheduled,
            titleSnapshot: "Attached schedule",
            promptSnapshot: "Run work",
            destinationSnapshot: .existingThread,
            targetConversationIDSnapshot: main.id,
            timeZoneIdentifierSnapshot: "UTC",
            providerIDSnapshot: "codex",
            effortSnapshot: "high",
            permissionModeSnapshot: "acceptEdits",
            workspaceKindSnapshot: .project,
            workspaceStrategySnapshot: .localCheckout,
            projectPathSnapshot: project.path,
            targetThread: target
        )
        fixture.context.insert(project)
        fixture.context.insert(run)
        try fixture.context.save()
        var reconciledIDs: [String] = []
        let services = fixture.makeServices(terminalConversationReconciliation: {
            reconciledIDs.append($0)
        })

        await services.coordinator.persistTerminalResult(
            .failed(message: "Preparation failed"),
            runID: run.persistentModelID,
            finishedAt: fixture.actionDate
        )

        XCTAssertEqual(run.status, .failure)
        XCTAssertTrue(main.isUnread)
        XCTAssertFalse(sibling.isUnread)
        XCTAssertEqual(Set(reconciledIDs), Set([main.id, sibling.id]))
        XCTAssertEqual(target.modifiedAt, fixture.actionDate)
    }

    func testRunNowBusyTargetPublishesVisibleClaimError() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let project = Project(path: "/tmp/run-now-target", name: "Run now target")
        let target = AgentThread(name: "Pinned target", isPinned: true, project: project)
        let conversation = Conversation(id: "run-now-target-main", provider: "codex", thread: target)
        target.conversations = [conversation]
        project.threads = [target]
        fixture.context.insert(project)
        let definition = try fixture.insertDefinition(
            id: "busy-run-now",
            project: project,
            workspaceStrategy: .localCheckout
        )
        definition.destination = .existingThread
        definition.targetThread = target
        try fixture.context.save()
        let services = fixture.makeServices(preflightValidator: { _ in .targetBusy })
        var claimErrors: [String] = []
        services.coordinator.setSchedulingStateDidChange { _, errorMessage in
            if let errorMessage {
                claimErrors.append(errorMessage)
            }
        }
        let request = ScheduledTaskRunNowRequest.prepare(
            definition: definition,
            triggeredAt: fixture.actionDate,
            recurrenceCalculator: ScheduledTaskRecurrenceCalculator()
        )

        XCTAssertTrue(services.coordinator.startRunNow(request))
        await services.coordinator.waitUntilIdle()

        XCTAssertEqual(
            claimErrors,
            ["This scheduled task couldn't start because its pinned target thread is busy. Try again when the thread is idle."]
        )
        XCTAssertTrue(try fixture.runs().isEmpty)
    }

    func testSchedulingStateChangesAfterClaimAndTerminalCompletion() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        try fixture.insertDefinition(id: "state-change", projectPath: "/tmp/state-change")
        let executionProbe = ScheduledTaskBlockingProbe()
        let services = fixture.makeServices(executionProbe: executionProbe)
        var changedDefinitionIDs: [String] = []
        services.coordinator.setSchedulingStateDidChange { definitionID, _ in
            changedDefinitionIDs.append(definitionID)
        }

        XCTAssertTrue(services.coordinator.startDueTask(definitionID: "state-change", at: fixture.actionDate))
        try await waitUntil("expected claimed run to enter execution") {
            await executionProbe.snapshot().entryCount == 1
        }
        XCTAssertEqual(changedDefinitionIDs, ["state-change"])

        await executionProbe.release()
        await services.coordinator.waitUntilIdle()
        XCTAssertEqual(changedDefinitionIDs, ["state-change", "state-change"])
    }

    func testDuePendingOccurrenceWaitsForUnknownNonterminalRun() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definition = try fixture.insertDefinition(id: "held-pending", projectPath: "/tmp/held-pending")
        definition.nextOccurrenceAt = fixture.actionDate.addingTimeInterval(60)
        definition.pendingOccurrenceAt = fixture.actionDate
        let run = try fixture.insertRun(definition: definition, status: .running)
        run.statusRawValue = "future-nonterminal-status"
        try fixture.context.save()
        let services = fixture.makeServices()

        XCTAssertEqual(try services.coordinator.startDueTasks(at: fixture.actionDate), 0)
        XCTAssertTrue(services.coordinator.definitionIDsBeingClaimed.isEmpty)
        XCTAssertTrue(try fixture.runs().allSatisfy { !$0.hasKnownTerminalStatus })
    }

    func testDueNextOccurrenceStillCoalescesWhilePendingIsHeldByActiveRun() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definition = try fixture.insertDefinition(id: "newer-overlap", projectPath: "/tmp/newer-overlap")
        definition.nextOccurrenceAt = fixture.actionDate
        definition.pendingOccurrenceAt = fixture.actionDate.addingTimeInterval(-60)
        _ = try fixture.insertRun(definition: definition, status: .running)
        let services = fixture.makeServices()

        XCTAssertEqual(try services.coordinator.startDueTasks(at: fixture.actionDate), 1)
        await services.coordinator.waitUntilIdle()

        XCTAssertEqual(definition.pendingOccurrenceAt, fixture.actionDate)
        XCTAssertEqual(try fixture.runs().count, 1)
    }

    func testInvalidDefinitionPublishesDefinitionFailureWithoutCreatingConversationWork() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definition = try fixture.insertDefinition(id: "definition-notification", projectPath: "/tmp/definition-notification")
        definition.nextOccurrenceAt = nil
        definition.timeZoneIdentifier = "invalid/timezone"
        try fixture.context.save()
        var definitionIDs: [String] = []
        var titles: [String] = []
        var reasons: [String] = []
        let services = fixture.makeServices(
            definitionFailureNotification: { definitionID, title, reason in
                definitionIDs.append(definitionID)
                titles.append(title)
                reasons.append(reason)
            }
        )

        XCTAssertEqual(try services.coordinator.startDueTasks(at: fixture.actionDate), 1)
        await services.coordinator.waitUntilIdle()

        XCTAssertEqual(definitionIDs, [definition.id])
        XCTAssertEqual(titles, [definition.title])
        XCTAssertEqual(reasons.count, 1)
        XCTAssertEqual(reasons.first, definition.pauseReason)
        XCTAssertTrue(try fixture.runs().isEmpty)
        XCTAssertEqual(services.notificationManager.refreshBadgeCountCalls, 0)
        XCTAssertTrue(services.notificationManager.handleEventCalls.isEmpty)
    }

    func testKeepAwakeCoversMaterializationAndReleasesAfterCompletion() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        try fixture.insertDefinition(id: "materializing-power", projectPath: "/tmp/materializing-power")
        let materializationProbe = ScheduledTaskBlockingProbe()
        let services = fixture.makeServices(materializationProbe: materializationProbe)

        XCTAssertEqual(try services.coordinator.startDueTasks(at: fixture.actionDate), 1)
        try await waitUntil("expected materialization to start") {
            await materializationProbe.snapshot().entryCount == 1
        }
        let run = try XCTUnwrap(fixture.runs().first)
        let source = KeepAwakeActivitySource.scheduledTaskRun(runID: run.id)
        XCTAssertTrue(services.keepAwakeService.isActive(source))

        await materializationProbe.release()
        await services.coordinator.waitUntilIdle()
        XCTAssertFalse(services.keepAwakeService.isActive(source))
        XCTAssertEqual(run.status, .success)
    }

    func testKeepAwakeCoversWorkspaceLockWaitAndReleasesBothSources() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        try fixture.insertDefinition(id: "first-power", projectPath: "/tmp/shared-power")
        try fixture.insertDefinition(id: "second-power", projectPath: "/tmp/shared-power/nested")
        let executionProbe = ScheduledTaskBlockingProbe()
        let services = fixture.makeServices(executionProbe: executionProbe)

        XCTAssertEqual(try services.coordinator.startDueTasks(at: fixture.actionDate), 2)
        try await waitUntil("expected one execution and one lock waiter") {
            await executionProbe.snapshot().entryCount == 1 &&
                (try? fixture.runs().count) == 2
        }
        XCTAssertEqual(services.keepAwakeService.activeSources.count, 2)

        await executionProbe.release()
        try await waitUntil("expected the lock waiter to execute") {
            await executionProbe.snapshot().entryCount == 2
        }
        await executionProbe.release()
        await services.coordinator.waitUntilIdle()
        XCTAssertTrue(services.keepAwakeService.activeSources.isEmpty)
    }

    func testKeepAwakeReleasesAfterMaterializationAndExecutionFailures() async throws {
        for failsDuringMaterialization in [true, false] {
            let fixture = try ScheduledTaskCoordinatorFixture()
            let definitionID = failsDuringMaterialization ? "materialization-power-failure" : "execution-power-failure"
            try fixture.insertDefinition(id: definitionID, projectPath: "/tmp/\(definitionID)")
            let services = fixture.makeServices(
                materializationFailureIDs: failsDuringMaterialization ? [definitionID] : [],
                executionFailureIDs: failsDuringMaterialization ? [] : [definitionID]
            )

            XCTAssertTrue(services.coordinator.startDueTask(definitionID: definitionID, at: fixture.actionDate))
            await services.coordinator.waitUntilIdle()

            XCTAssertEqual(try fixture.runs().first?.status, .failure)
            XCTAssertTrue(services.keepAwakeService.activeSources.isEmpty)
        }
    }

    func testFailedRunRetainsPowerUntilTerminalStateAndUnreadAreDurable() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definitionID = "durable-failure"
        try fixture.insertDefinition(id: definitionID, projectPath: "/tmp/durable-failure")
        let unrelatedDefinition = try fixture.insertDefinition(id: "unrelated", projectPath: "/tmp/unrelated")
        let retryProbe = ScheduledTaskBlockingProbe()
        var saveAttempts = 0
        let services = fixture.makeServices(
            materializationFailureIDs: [definitionID],
            saveTerminalState: {
                saveAttempts += 1
                if saveAttempts == 1 {
                    throw ScheduledTaskCoordinatorTestError.pendingSave
                }
                try fixture.context.save()
            },
            persistenceRetryWait: {
                await retryProbe.enter("terminal-save")
            }
        )

        XCTAssertTrue(services.coordinator.startDueTask(definitionID: definitionID, at: fixture.actionDate))
        try await waitUntil("expected terminal persistence retry") {
            await retryProbe.snapshot().entryCount == 1
        }
        let retryingRun = try XCTUnwrap(fixture.runs().first)
        let source = KeepAwakeActivitySource.scheduledTaskRun(runID: retryingRun.id)
        XCTAssertTrue(services.keepAwakeService.isActive(source))
        XCTAssertEqual(retryingRun.status, .failure)
        unrelatedDefinition.title = "Unrelated edit during retry"

        await retryProbe.release()
        await services.coordinator.waitUntilIdle()

        let persistedRun = try XCTUnwrap(fixture.runs().first)
        XCTAssertEqual(persistedRun.status, .failure)
        XCTAssertEqual(persistedRun.thread?.conversations.first(where: \.isMain)?.isUnread, true)
        XCTAssertFalse(services.keepAwakeService.isActive(source))
        XCTAssertEqual(services.notificationManager.refreshBadgeCountCalls, 1)
        XCTAssertEqual(unrelatedDefinition.title, "Unrelated edit during retry")
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testProvenancePersistenceFailureReturnsRunToClaimedForRecovery() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definitionID = "provenance-retry"
        try fixture.insertDefinition(id: definitionID, projectPath: "/tmp/provenance-retry")
        let services = fixture.makeServices(provenanceFailureIDs: [definitionID])

        XCTAssertTrue(services.coordinator.startDueTask(definitionID: definitionID, at: fixture.actionDate))
        await services.coordinator.waitUntilIdle()

        let run = try XCTUnwrap(fixture.runs().first)
        XCTAssertEqual(run.status, .claimed)
        XCTAssertNil(run.preparationStartedAt)
        XCTAssertNil(run.preparedWorkspaceRoot)
        XCTAssertNil(run.thread)
        XCTAssertNotNil(run.lastError)
        XCTAssertTrue(services.keepAwakeService.activeSources.isEmpty)
        XCTAssertEqual(services.notificationManager.refreshBadgeCountCalls, 0)
    }

    func testShellFailurePersistenceExhaustionIsDurablyReapplied() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definitionID = "shell-provenance-retry"
        try fixture.insertDefinition(id: definitionID, projectPath: "/tmp/shell-provenance-retry")
        var reconciledConversationIDs: [String] = []
        let services = fixture.makeServices(
            provenanceFailureIDs: [definitionID],
            terminalConversationReconciliation: { conversationID in
                reconciledConversationIDs.append(conversationID)
            }
        )

        XCTAssertTrue(services.coordinator.startDueTask(definitionID: definitionID, at: fixture.actionDate))
        await services.coordinator.waitUntilIdle()

        let run = try XCTUnwrap(fixture.runs().first)
        XCTAssertEqual(run.status, .failure)
        XCTAssertNotNil(run.finishedAt)
        XCTAssertNotNil(run.thread)
        XCTAssertEqual(run.thread?.conversations.first(where: \.isMain)?.isUnread, true)
        XCTAssertTrue(services.keepAwakeService.activeSources.isEmpty)
        XCTAssertEqual(services.notificationManager.refreshBadgeCountCalls, 1)
        let conversationID = try XCTUnwrap(run.thread?.conversations.first(where: \.isMain)?.id)
        XCTAssertEqual(reconciledConversationIDs, [conversationID])
    }

    func testTerminalReconciliationIncludesSideConversationsCreatedDuringRun() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definition = try fixture.insertDefinition(id: "side-conversation", projectPath: "/tmp/side-conversation")
        let executionProbe = ScheduledTaskBlockingProbe()
        var reconciledConversationIDs: [String] = []
        let services = fixture.makeServices(
            executionProbe: executionProbe,
            terminalConversationReconciliation: { conversationID in
                reconciledConversationIDs.append(conversationID)
            }
        )

        XCTAssertTrue(services.coordinator.startDueTask(definitionID: definition.id, at: fixture.actionDate))
        try await waitUntil("expected scheduled execution before creating a side conversation") {
            await executionProbe.snapshot().entryCount == 1
        }
        let run = try XCTUnwrap(fixture.runs().first)
        let thread = try XCTUnwrap(run.thread)
        let mainConversationID = try XCTUnwrap(thread.conversations.first(where: \.isMain)?.id)
        let sideConversation = Conversation(isMain: false, displayOrder: 1, thread: thread)
        fixture.context.insert(sideConversation)
        try fixture.context.save()

        await executionProbe.release()
        await services.coordinator.waitUntilIdle()

        XCTAssertEqual(
            Set(reconciledConversationIDs),
            Set([mainConversationID, sideConversation.id])
        )
    }

    func testShutdownCancelsMaterializationPreservesPendingAndReleasesPower() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definition = try fixture.insertDefinition(id: "shutdown", projectPath: "/tmp/shutdown")
        let materializationProbe = ScheduledTaskBlockingProbe()
        let services = fixture.makeServices(materializationProbe: materializationProbe)

        XCTAssertTrue(services.coordinator.startDueTask(definitionID: definition.id, at: fixture.actionDate))
        try await waitUntil("expected shutdown run to materialize") {
            await materializationProbe.snapshot().entryCount == 1
        }
        let run = try XCTUnwrap(fixture.runs().first)
        definition.pendingOccurrenceAt = fixture.actionDate
        try fixture.context.save()

        let shutdown = Task { @MainActor in
            await services.coordinator.shutdown()
        }
        await Task.yield()
        await materializationProbe.release()
        await shutdown.value

        XCTAssertEqual(run.status, .interrupted)
        XCTAssertEqual(run.thread?.conversations.first(where: \.isMain)?.isUnread, true)
        XCTAssertEqual(definition.pendingOccurrenceAt, fixture.actionDate)
        XCTAssertTrue(services.executor.stopRunIDs.isEmpty)
        XCTAssertTrue(services.keepAwakeService.activeSources.isEmpty)
        XCTAssertTrue(services.coordinator.activeRunIDs.isEmpty)
    }

    func testShutdownCancelsWorkspaceWaitAndExecutionWithoutUsingUserStop() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        try fixture.insertDefinition(id: "executing-shutdown", projectPath: "/tmp/shared-shutdown")
        try fixture.insertDefinition(id: "waiting-shutdown", projectPath: "/tmp/shared-shutdown/nested")
        let executionProbe = ScheduledTaskBlockingProbe()
        let services = fixture.makeServices(executionProbe: executionProbe)

        XCTAssertEqual(try services.coordinator.startDueTasks(at: fixture.actionDate), 2)
        try await waitUntil("expected execution and workspace waiter before shutdown") {
            await executionProbe.snapshot().entryCount == 1 &&
                services.keepAwakeService.activeSources.count == 2
        }

        let shutdown = Task { @MainActor in
            await services.coordinator.shutdown()
        }
        await Task.yield()
        await executionProbe.release()
        await shutdown.value

        XCTAssertTrue(try fixture.runs().allSatisfy { $0.status == .interrupted })
        XCTAssertTrue(services.executor.stopRunIDs.isEmpty)
        XCTAssertTrue(services.keepAwakeService.activeSources.isEmpty)
        XCTAssertTrue(services.coordinator.activeRunIDs.isEmpty)
    }

    func testShutdownWaitsForPausedPreflightRaceWithoutLaunchingRun() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definition = try fixture.insertDefinition(id: "preflight", projectPath: "/tmp/preflight")
        let preflightProbe = ScheduledTaskBlockingProbe()
        let services = fixture.makeServices(preflightValidator: { snapshot in
            await preflightProbe.enter(snapshot.definitionID)
            return scheduledTaskReadyOutcome(for: snapshot)
        })

        XCTAssertTrue(services.coordinator.startDueTask(definitionID: definition.id, at: fixture.actionDate))
        try await waitUntil("expected preflight to start") {
            await preflightProbe.snapshot().entryCount == 1
        }
        definition.state = .paused
        definition.revision += 1
        try fixture.context.save()

        let shutdown = Task { @MainActor in
            await services.coordinator.shutdown()
        }
        await Task.yield()
        await preflightProbe.release()
        await shutdown.value

        XCTAssertEqual(definition.state, .paused)
        XCTAssertTrue(try fixture.runs().isEmpty)
        XCTAssertTrue(services.keepAwakeService.activeSources.isEmpty)
        XCTAssertTrue(services.coordinator.activeRunIDs.isEmpty)
    }

    func testShutdownPermanentlyRejectsEveryLaunchSurface() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let definition = try fixture.insertDefinition(id: "closed", projectPath: "/tmp/closed")
        let claimedRun = try fixture.insertRun(definition: definition, status: .claimed)
        let services = fixture.makeServices()

        await services.coordinator.shutdown()

        let request = ScheduledTaskRunNowRequest(
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: fixture.actionDate,
            triggeredAt: fixture.actionDate,
            occurrenceSource: .scheduled
        )
        XCTAssertFalse(services.coordinator.startDueTask(definitionID: definition.id, at: fixture.actionDate))
        XCTAssertFalse(services.coordinator.startRunNow(request))
        XCTAssertEqual(services.coordinator.resumeClaimedRuns([claimedRun.persistentModelID]), 0)
        XCTAssertEqual(try services.coordinator.startDueTasks(at: fixture.actionDate), 0)
        XCTAssertTrue(services.coordinator.activeRunIDs.isEmpty)
    }

}
