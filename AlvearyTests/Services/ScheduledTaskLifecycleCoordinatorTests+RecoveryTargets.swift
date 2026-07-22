import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskLifecycleCoordinatorTests {
    func testRecoveryReadinessRechecksTargetAfterPreflight() async {
        let state = ScheduledRecoveryReadinessTestState()
        let snapshot = recoveryTargetSnapshot(runID: "target-run", conversationID: "target-main")
        let validator = ScheduledTaskRecoveryReadinessValidator(
            validatePreflight: { preflight in
                state.validatedDefinitionIDs.append(preflight.definitionID)
                state.targetIsReady = false
                return .ready(snapshot.claimedWorkspaceIdentities)
            },
            targetIsReady: { _ in
                state.readinessCheckCount += 1
                return state.targetIsReady
            }
        )

        let isReady = await validator.isReady(snapshot)

        XCTAssertFalse(isReady)
        XCTAssertEqual(state.readinessCheckCount, 2)
        XCTAssertEqual(state.validatedDefinitionIDs, [snapshot.preflight.definitionID])
    }

    func testActivationSelectsAtMostOneRecoveredRunPerExistingTarget() async {
        let later = recoveryTargetSnapshot(
            runID: "later-run",
            conversationID: "target-main",
            claimedAt: Date(timeIntervalSinceReferenceDate: 2_000)
        )
        let earlier = recoveryTargetSnapshot(
            runID: "earlier-run",
            conversationID: "target-main",
            claimedAt: Date(timeIntervalSinceReferenceDate: 1_000)
        )
        var validatedRunIDs: [String] = []
        var recoveredSafeRunIDs = Set<String>()
        let coordinator = ScheduledTaskLifecycleCoordinator(
            notificationCenter: NotificationCenter(),
            now: { Date(timeIntervalSinceReferenceDate: 20_000) },
            sleep: { _ in },
            loadRecoverySnapshots: { [later, earlier] },
            validateRecoveryReadiness: { snapshot in
                validatedRunIDs.append(snapshot.runID)
                return true
            },
            recoverPersistedRuns: { _, safeRunIDs in
                recoveredSafeRunIDs = safeRunIDs
                return ScheduledTaskRunRecoveryResult(resumedRunIDs: [], interruptedRunIDs: [])
            },
            resumeRecoveredRuns: { _ in 0 },
            startDueTasks: { _ in 0 },
            loadClaimingDefinitionIDs: { [] },
            loadNextDeadline: { _, _ in nil },
            beginSchedulerShutdown: {},
            prepareRunsForTermination: { _ in Self.emptyRecoveryTerminationPreparation }
        )

        await coordinator.activateAfterProviderRefresh()

        XCTAssertEqual(validatedRunIDs, ["earlier-run"])
        XCTAssertEqual(recoveredSafeRunIDs, ["earlier-run"])
    }
}

private extension ScheduledTaskLifecycleCoordinatorTests {
    static var emptyRecoveryTerminationPreparation: ScheduledTaskTerminationPreparation {
        ScheduledTaskTerminationPreparation(
            interruptedRunIDs: [],
            conversationIDsToTerminate: [],
            controllerFlushFailures: []
        )
    }

    func recoveryTargetSnapshot(
        runID: String,
        conversationID: String,
        claimedAt: Date = Date(timeIntervalSinceReferenceDate: 900)
    ) -> ScheduledTaskRecoveryReadinessSnapshot {
        let workspaceIdentities = ScheduledTaskWorkspaceIdentitySnapshot(projectRoot: nil, grantedRoots: [])
        return ScheduledTaskRecoveryReadinessSnapshot(
            runID: runID,
            claimedAt: claimedAt,
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
                grantedRoots: [],
                destination: .existingThread,
                target: ScheduledTaskTargetSnapshot(
                    conversationID: conversationID,
                    threadName: "Pinned target",
                    providerID: "codex",
                    model: nil,
                    effort: "medium",
                    permissionMode: "on-request",
                    planModeEnabled: false,
                    speedMode: "standard",
                    workspaceKind: .privateWorkspace,
                    workspaceStrategy: .worktree,
                    projectPath: nil,
                    grantedRoots: []
                )
            ),
            claimedWorkspaceIdentities: workspaceIdentities
        )
    }
}

@MainActor
private final class ScheduledRecoveryReadinessTestState {
    var targetIsReady = true
    var readinessCheckCount = 0
    var validatedDefinitionIDs: [String] = []
}
