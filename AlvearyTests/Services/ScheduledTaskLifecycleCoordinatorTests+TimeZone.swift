import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskLifecycleCoordinatorTests {
    func testActivationRebasesLocalTimeZoneBeforeStartingDueTasks() async {
        let notificationCenter = NotificationCenter()
        let actionDate = Date(timeIntervalSinceReferenceDate: 20_000)
        var order: [String] = []
        var publishedChangeCount = 0
        let coordinator = makeTimeZoneCoordinator(
            notificationCenter: notificationCenter,
            actionDate: actionDate,
            order: { order.append($0) },
            publishChange: { publishedChangeCount += 1 }
        )

        await coordinator.activateAfterProviderRefresh()

        XCTAssertEqual(order, ["load", "recover", "rebase", "publish", "resume", "due"])
        XCTAssertEqual(publishedChangeCount, 1)
    }

    func testSystemTimeZoneChangeRebasesBeforeReconciliationAndPublishes() async {
        let notificationCenter = NotificationCenter()
        let actionDate = Date(timeIntervalSinceReferenceDate: 30_000)
        var order: [String] = []
        var publishedChangeCount = 0
        let coordinator = makeTimeZoneCoordinator(
            notificationCenter: notificationCenter,
            actionDate: actionDate,
            order: { order.append($0) },
            publishChange: { publishedChangeCount += 1 }
        )
        await coordinator.activateAfterProviderRefresh()
        order.removeAll()
        publishedChangeCount = 0

        notificationCenter.post(name: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil)

        XCTAssertEqual(order, ["rebase", "due", "publish"])
        XCTAssertEqual(publishedChangeCount, 1)
    }
}

@MainActor
private extension ScheduledTaskLifecycleCoordinatorTests {
    func makeTimeZoneCoordinator(
        notificationCenter: NotificationCenter,
        actionDate: Date,
        order: @escaping (String) -> Void,
        publishChange: @escaping () -> Void
    ) -> ScheduledTaskLifecycleCoordinator {
        ScheduledTaskLifecycleCoordinator(
            notificationCenter: notificationCenter,
            now: { actionDate },
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) },
            loadRecoverySnapshots: {
                order("load")
                return []
            },
            validateRecoveryReadiness: { _ in true },
            recoverPersistedRuns: { _, _ in
                order("recover")
                return ScheduledTaskRunRecoveryResult(resumedRunIDs: [], interruptedRunIDs: [])
            },
            resumeRecoveredRuns: { _ in
                order("resume")
                return 0
            },
            startDueTasks: { _ in
                order("due")
                return 0
            },
            loadClaimingDefinitionIDs: { [] },
            loadNextDeadline: { _, _ in nil },
            beginSchedulerShutdown: {},
            prepareRunsForTermination: { _ in
                ScheduledTaskTerminationPreparation(
                    interruptedRunIDs: [],
                    conversationIDsToTerminate: [],
                    controllerFlushFailures: []
                )
            },
            publishRecoveryStateChange: {
                order("publish")
                publishChange()
            },
            rebaseLocalTimeZone: { _ in
                order("rebase")
                return true
            }
        )
    }
}
