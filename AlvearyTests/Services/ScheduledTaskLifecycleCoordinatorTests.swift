import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ScheduledTaskLifecycleCoordinatorTests: XCTestCase {
    func testRecoveryReadinessRequiresExactCurrentWorkspaceIdentities() async {
        let claimed = ScheduledTaskWorkspaceIdentitySnapshot(
            projectRoot: nil,
            grantedRoots: [ScheduledTaskRootIdentitySnapshot(
                path: "/tmp/grant",
                identity: TaskWorkspaceFileSystemIdentity(systemNumber: 1, fileNumber: 2)
            )]
        )
        let current = ScheduledTaskWorkspaceIdentitySnapshot(
            projectRoot: nil,
            grantedRoots: [ScheduledTaskRootIdentitySnapshot(
                path: "/tmp/grant",
                identity: TaskWorkspaceFileSystemIdentity(systemNumber: 1, fileNumber: 3)
            )]
        )
        let snapshot = recoverySnapshot(runID: "identity", workspaceIdentities: claimed)
        let validator = ScheduledTaskRecoveryReadinessValidator { preflight in
            XCTAssertEqual(preflight.grantedRoots, ["/tmp/grant"])
            return .ready(current)
        }

        let isReady = await validator.isReady(snapshot)
        XCTAssertFalse(isReady)
    }

    func testActivationValidatesRecoveryBeforeResumingAndStartingDueWork() async {
        let notificationCenter = NotificationCenter()
        let actionDate = Date(timeIntervalSinceReferenceDate: 10_000)
        let snapshots = recoverySnapshots()
        var order: [String] = []
        var recoveredSafeRunIDs = Set<String>()
        var dueStartDates: [Date] = []
        let coordinator = ScheduledTaskLifecycleCoordinator(
            notificationCenter: notificationCenter,
            now: { actionDate },
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) },
            loadRecoverySnapshots: {
                order.append("load")
                return snapshots
            },
            validateRecoveryReadiness: { snapshot in
                order.append("validate-\(snapshot.runID)")
                return snapshot.runID == "safe"
            },
            recoverPersistedRuns: { _, safeRunIDs in
                order.append("recover")
                recoveredSafeRunIDs = safeRunIDs
                return ScheduledTaskRunRecoveryResult(resumedRunIDs: [], interruptedRunIDs: [])
            },
            resumeRecoveredRuns: { _ in
                order.append("resume")
                return 0
            },
            startDueTasks: {
                order.append("due")
                dueStartDates.append($0)
                return 0
            },
            loadClaimingDefinitionIDs: { [] },
            loadNextDeadline: { _, _ in nil },
            beginSchedulerShutdown: {},
            prepareRunsForTermination: { _ in Self.emptyTerminationPreparation }
        )
        XCTAssertFalse(coordinator.canStartManualRuns)

        await coordinator.activateAfterProviderRefresh()

        XCTAssertTrue(coordinator.canStartManualRuns)
        XCTAssertEqual(order, ["load", "validate-safe", "validate-unsafe", "recover", "resume", "due"])
        XCTAssertEqual(recoveredSafeRunIDs, ["safe"])
        XCTAssertEqual(dueStartDates, [actionDate])
        XCTAssertNil(coordinator.scheduledDeadline)
    }

    func testRecoveryInterruptionPublishesManagementStateChange() async throws {
        let actionDate = Date(timeIntervalSinceReferenceDate: 12_000)
        let fixture = try makeDeadlineFixture(actionDate: actionDate)
        let definition = try XCTUnwrap(fixture.context.resolveScheduledTask(id: fixture.claimingDefinitionID))
        let run = ScheduledTaskRun(
            snapshotting: definition,
            occurrenceID: "interrupted-recovery",
            occurrenceAt: actionDate,
            triggerKind: .scheduled,
            status: .running
        )
        fixture.context.insert(run)
        try fixture.context.save()
        var publishedChangeCount = 0
        let coordinator = ScheduledTaskLifecycleCoordinator(
            notificationCenter: NotificationCenter(),
            now: { actionDate },
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) },
            loadRecoverySnapshots: { [] },
            validateRecoveryReadiness: { _ in true },
            recoverPersistedRuns: { _, _ in
                ScheduledTaskRunRecoveryResult(resumedRunIDs: [], interruptedRunIDs: [run.persistentModelID])
            },
            resumeRecoveredRuns: { _ in 0 },
            startDueTasks: { _ in 0 },
            loadClaimingDefinitionIDs: { [] },
            loadNextDeadline: { _, _ in nil },
            beginSchedulerShutdown: {},
            prepareRunsForTermination: { _ in Self.emptyTerminationPreparation },
            publishRecoveryStateChange: { publishedChangeCount += 1 }
        )

        await coordinator.activateAfterProviderRefresh()

        XCTAssertEqual(publishedChangeCount, 1)
    }

    func testScheduledDeadlineFiresAndRearmsForTheFollowingDeadline() async throws {
        let notificationCenter = NotificationCenter()
        let actionDate = Date(timeIntervalSinceReferenceDate: 15_000)
        let sleeper = ScheduledLifecycleTestSleeper()
        var dueStartCount = 0
        var deadlineLoadCount = 0
        let coordinator = ScheduledTaskLifecycleCoordinator(
            notificationCenter: notificationCenter,
            now: { actionDate },
            sleep: { duration in try await sleeper.sleep(duration) },
            loadRecoverySnapshots: { [] },
            validateRecoveryReadiness: { _ in true },
            recoverPersistedRuns: { _, _ in
                ScheduledTaskRunRecoveryResult(resumedRunIDs: [], interruptedRunIDs: [])
            },
            resumeRecoveredRuns: { _ in 0 },
            startDueTasks: { _ in
                dueStartCount += 1
                return 0
            },
            loadClaimingDefinitionIDs: { [] },
            loadNextDeadline: { _, _ in
                deadlineLoadCount += 1
                let offset: TimeInterval = deadlineLoadCount == 1 ? 10 : 20
                return actionDate.addingTimeInterval(offset)
            },
            beginSchedulerShutdown: {},
            prepareRunsForTermination: { _ in Self.emptyTerminationPreparation }
        )

        await coordinator.activateAfterProviderRefresh()
        try await scheduledTaskLifecycleWaitUntil("expected initial deadline sleep") {
            sleeper.pendingDurations() == [.seconds(10)]
        }
        XCTAssertEqual(dueStartCount, 1)
        XCTAssertEqual(coordinator.scheduledDeadline, actionDate.addingTimeInterval(10))

        sleeper.resumeNext()
        try await scheduledTaskLifecycleWaitUntil("expected fired deadline to rearm") {
            let pendingDurations = sleeper.pendingDurations()
            return dueStartCount == 2 &&
                coordinator.scheduledDeadline == actionDate.addingTimeInterval(20) &&
                pendingDurations == [.seconds(20)]
        }

        _ = try coordinator.prepareForTermination(at: actionDate)
        try await scheduledTaskLifecycleWaitUntil("expected termination to cancel rearmed sleep") {
            sleeper.pendingDurations().isEmpty
        }
    }

    func testActivationFailureRetriesActivationAfterConfiguredDelay() async throws {
        let notificationCenter = NotificationCenter()
        let actionDate = Date(timeIntervalSinceReferenceDate: 16_000)
        let sleeper = ScheduledLifecycleTestSleeper()
        var loadCount = 0
        var dueStartCount = 0
        var handledErrorCount = 0
        let coordinator = ScheduledTaskLifecycleCoordinator(
            notificationCenter: notificationCenter,
            now: { actionDate },
            sleep: { duration in try await sleeper.sleep(duration) },
            loadRecoverySnapshots: {
                loadCount += 1
                if loadCount == 1 {
                    throw ScheduledTaskLifecycleTestError.plannedFailure
                }
                return []
            },
            validateRecoveryReadiness: { _ in true },
            recoverPersistedRuns: { _, _ in
                ScheduledTaskRunRecoveryResult(resumedRunIDs: [], interruptedRunIDs: [])
            },
            resumeRecoveredRuns: { _ in 0 },
            startDueTasks: { _ in
                dueStartCount += 1
                return 0
            },
            loadClaimingDefinitionIDs: { [] },
            loadNextDeadline: { _, _ in nil },
            beginSchedulerShutdown: {},
            prepareRunsForTermination: { _ in Self.emptyTerminationPreparation },
            retryDelay: 5,
            handleError: { _ in handledErrorCount += 1 }
        )

        await coordinator.activateAfterProviderRefresh()
        try await scheduledTaskLifecycleWaitUntil("expected activation retry sleep") {
            sleeper.pendingDurations() == [.seconds(5)]
        }
        XCTAssertEqual(coordinator.scheduledDeadline, actionDate.addingTimeInterval(5))
        XCTAssertEqual(loadCount, 1)
        XCTAssertEqual(dueStartCount, 0)
        XCTAssertEqual(handledErrorCount, 1)

        sleeper.resumeNext()
        try await scheduledTaskLifecycleWaitUntil("expected activation retry to succeed") {
            loadCount == 2 && dueStartCount == 1 && coordinator.scheduledDeadline == nil
        }

        _ = try coordinator.prepareForTermination(at: actionDate)
    }

    func testReconciliationFailureRetriesReconciliationAfterConfiguredDelay() async throws {
        let notificationCenter = NotificationCenter()
        let actionDate = Date(timeIntervalSinceReferenceDate: 17_000)
        let sleeper = ScheduledLifecycleTestSleeper()
        var dueStartCount = 0
        var handledErrorCount = 0
        let coordinator = ScheduledTaskLifecycleCoordinator(
            notificationCenter: notificationCenter,
            now: { actionDate },
            sleep: { duration in try await sleeper.sleep(duration) },
            loadRecoverySnapshots: { [] },
            validateRecoveryReadiness: { _ in true },
            recoverPersistedRuns: { _, _ in
                ScheduledTaskRunRecoveryResult(resumedRunIDs: [], interruptedRunIDs: [])
            },
            resumeRecoveredRuns: { _ in 0 },
            startDueTasks: { _ in
                dueStartCount += 1
                if dueStartCount == 1 {
                    throw ScheduledTaskLifecycleTestError.plannedFailure
                }
                return 0
            },
            loadClaimingDefinitionIDs: { [] },
            loadNextDeadline: { _, _ in nil },
            beginSchedulerShutdown: {},
            prepareRunsForTermination: { _ in Self.emptyTerminationPreparation },
            retryDelay: 7,
            handleError: { _ in handledErrorCount += 1 }
        )

        await coordinator.activateAfterProviderRefresh()
        try await scheduledTaskLifecycleWaitUntil("expected reconciliation retry sleep") {
            sleeper.pendingDurations() == [.seconds(7)]
        }
        XCTAssertEqual(coordinator.scheduledDeadline, actionDate.addingTimeInterval(7))
        XCTAssertEqual(dueStartCount, 1)
        XCTAssertEqual(handledErrorCount, 1)

        sleeper.resumeNext()
        try await scheduledTaskLifecycleWaitUntil("expected reconciliation retry to succeed") {
            dueStartCount == 2 && coordinator.scheduledDeadline == nil
        }

        _ = try coordinator.prepareForTermination(at: actionDate)
    }

    func testDefinitionClockTimeZoneAndExplicitReconciliationRescanDueTasks() async {
        let notificationCenter = NotificationCenter()
        let actionDate = Date(timeIntervalSinceReferenceDate: 20_000)
        var dueStartCount = 0
        let coordinator = makeCoordinator(
            notificationCenter: notificationCenter,
            now: actionDate,
            startDueTasks: { _ in
                dueStartCount += 1
                return 0
            }
        )
        await coordinator.activateAfterProviderRefresh()

        notificationCenter.post(name: .scheduledTasksChanged, object: nil)
        notificationCenter.post(name: NSNotification.Name.NSSystemClockDidChange, object: nil)
        notificationCenter.post(name: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil)
        coordinator.reconcileAfterSystemChange()

        XCTAssertEqual(dueStartCount, 5)
    }

    func testTerminationClosesLaunchFenceBeforePersistingAndCancelsDeadline() async throws {
        let notificationCenter = NotificationCenter()
        let actionDate = Date(timeIntervalSinceReferenceDate: 30_000)
        var order: [String] = []
        var dueStartCount = 0
        let coordinator = ScheduledTaskLifecycleCoordinator(
            notificationCenter: notificationCenter,
            now: { actionDate },
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) },
            loadRecoverySnapshots: { [] },
            validateRecoveryReadiness: { _ in true },
            recoverPersistedRuns: { _, _ in
                ScheduledTaskRunRecoveryResult(resumedRunIDs: [], interruptedRunIDs: [])
            },
            resumeRecoveredRuns: { _ in 0 },
            startDueTasks: { _ in
                dueStartCount += 1
                return 0
            },
            loadClaimingDefinitionIDs: { [] },
            loadNextDeadline: { _, _ in actionDate.addingTimeInterval(60) },
            beginSchedulerShutdown: { order.append("fence") },
            prepareRunsForTermination: { _ in
                order.append("persist")
                return Self.emptyTerminationPreparation
            }
        )
        await coordinator.activateAfterProviderRefresh()
        XCTAssertTrue(coordinator.canStartManualRuns)
        XCTAssertEqual(coordinator.scheduledDeadline, actionDate.addingTimeInterval(60))

        _ = try coordinator.prepareForTermination(at: actionDate)
        notificationCenter.post(name: .scheduledTasksChanged, object: nil)

        XCTAssertEqual(order, ["fence", "persist"])
        XCTAssertFalse(coordinator.canStartManualRuns)
        XCTAssertNil(coordinator.scheduledDeadline)
        XCTAssertEqual(dueStartCount, 1)
    }

    func testNextDeadlineIncludesPausedWorkAndExcludesClaimedDueInstant() throws {
        let actionDate = Date(timeIntervalSinceReferenceDate: 40_000)
        let fixture = try makeDeadlineFixture(actionDate: actionDate)

        let deadline = try ScheduledTaskLifecycleCoordinator.nextDeadline(
            in: fixture.context,
            at: actionDate,
            claimingDefinitionIDs: [fixture.claimingDefinitionID]
        )

        XCTAssertEqual(deadline, actionDate.addingTimeInterval(60))
    }

    func testNextDeadlineIgnoresHeldPendingButRetainsNextCadenceDuringUnknownRun() throws {
        let actionDate = Date(timeIntervalSinceReferenceDate: 50_000)
        let fixture = try makeDeadlineFixture(actionDate: actionDate)
        let claiming = try XCTUnwrap(fixture.context.resolveScheduledTask(id: fixture.claimingDefinitionID))
        claiming.nextOccurrenceAt = actionDate.addingTimeInterval(120)
        claiming.pendingOccurrenceAt = actionDate.addingTimeInterval(-10)
        let activeRun = ScheduledTaskRun(
            snapshotting: claiming,
            occurrenceID: "held-pending-run",
            occurrenceAt: actionDate.addingTimeInterval(-60),
            triggerKind: .scheduled,
            status: .running
        )
        activeRun.statusRawValue = "future-nonterminal-status"
        fixture.context.insert(activeRun)
        fixture.context.resolveScheduledTask(id: "paused")?.state = .completed
        try fixture.context.save()

        let deadline = try ScheduledTaskLifecycleCoordinator.nextDeadline(
            in: fixture.context,
            at: actionDate,
            claimingDefinitionIDs: []
        )

        XCTAssertEqual(deadline, actionDate.addingTimeInterval(120))
    }
}

private extension ScheduledTaskLifecycleCoordinatorTests {
    static var emptyTerminationPreparation: ScheduledTaskTerminationPreparation {
        ScheduledTaskTerminationPreparation(
            interruptedRunIDs: [],
            conversationIDsToTerminate: [],
            controllerFlushFailures: []
        )
    }

    func recoverySnapshot(
        runID: String,
        workspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot
    ) -> ScheduledTaskRecoveryReadinessSnapshot {
        ScheduledTaskRecoveryReadinessSnapshot(
            runID: runID,
            preflight: ScheduledTaskPreflightSnapshot(
                definitionID: "definition-\(runID)",
                definitionRevision: 1,
                scheduledOccurrenceAt: Date(timeIntervalSinceReferenceDate: 1_000),
                recurrence: .once(Date(timeIntervalSinceReferenceDate: 1_000)),
                timeZoneIdentifier: "UTC",
                providerID: "codex",
                model: nil,
                effort: "medium",
                permissionMode: "on-request",
                workspaceKind: .privateWorkspace,
                workspaceStrategy: .worktree,
                projectPath: nil,
                projectBaseRef: nil,
                projectRemoteName: nil,
                grantedRoots: workspaceIdentities.grantedRoots.map(\.path)
            ),
            claimedWorkspaceIdentities: workspaceIdentities
        )
    }

    func recoverySnapshots() -> [ScheduledTaskRecoveryReadinessSnapshot] {
        let workspaceIdentities = ScheduledTaskWorkspaceIdentitySnapshot(projectRoot: nil, grantedRoots: [])
        return [
            recoverySnapshot(runID: "safe", workspaceIdentities: workspaceIdentities),
            recoverySnapshot(runID: "unsafe", workspaceIdentities: workspaceIdentities)
        ]
    }

    func makeDeadlineFixture(actionDate: Date) throws -> ScheduledTaskDeadlineFixture {
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let claiming = ScheduledTask(
            id: "claiming",
            title: "Claiming",
            prompt: "Run",
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "UTC",
            providerID: "codex",
            nextOccurrenceAt: actionDate.addingTimeInterval(-10),
            pendingOccurrenceAt: actionDate.addingTimeInterval(120)
        )
        let paused = ScheduledTask(
            id: "paused",
            title: "Paused",
            prompt: "Run",
            state: .paused,
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "UTC",
            providerID: "codex",
            nextOccurrenceAt: actionDate.addingTimeInterval(60)
        )
        let completed = ScheduledTask(
            id: "completed",
            title: "Completed",
            prompt: "Run",
            state: .completed,
            recurrence: .once(actionDate),
            timeZoneIdentifier: "UTC",
            providerID: "codex",
            nextOccurrenceAt: actionDate.addingTimeInterval(10)
        )
        context.insert(claiming)
        context.insert(paused)
        context.insert(completed)
        try context.save()
        return ScheduledTaskDeadlineFixture(context: context, claimingDefinitionID: claiming.id)
    }

    func makeCoordinator(
        notificationCenter: NotificationCenter,
        now: Date,
        startDueTasks: @escaping ScheduledTaskLifecycleCoordinator.DueTaskStarter
    ) -> ScheduledTaskLifecycleCoordinator {
        ScheduledTaskLifecycleCoordinator(
            notificationCenter: notificationCenter,
            now: { now },
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) },
            loadRecoverySnapshots: { [] },
            validateRecoveryReadiness: { _ in true },
            recoverPersistedRuns: { _, _ in
                ScheduledTaskRunRecoveryResult(resumedRunIDs: [], interruptedRunIDs: [])
            },
            resumeRecoveredRuns: { _ in 0 },
            startDueTasks: startDueTasks,
            loadClaimingDefinitionIDs: { [] },
            loadNextDeadline: { _, _ in nil },
            beginSchedulerShutdown: {},
            prepareRunsForTermination: { _ in Self.emptyTerminationPreparation }
        )
    }
}

private struct ScheduledTaskDeadlineFixture {
    let context: ModelContext
    let claimingDefinitionID: String
}
