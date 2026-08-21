import Foundation
import UserNotifications
import XCTest

@testable import Alveary

/// Runs *inside* the app-hosted test process, so these assertions exercise the real production
/// defaults rather than a simulation of them. Delivery is spied rather than left live, so a
/// regression fails here quietly instead of in whichever unstubbed suite would have posted a real
/// banner onto the developer's desktop.
@MainActor
final class UserNotificationGatewayTests: XCTestCase {
    func testHostedTestProcessSuppressesTheGateway() {
        XCTAssertTrue(
            UserNotificationGateway.isSuppressed,
            "Hosted-test detection regressed; every unstubbed poster now reaches the real Notification Center"
        )
    }

    func testSuppressedGatewayReportsDeniedAndDeclinesAuthorization() async {
        let status = await UserNotificationGateway.authorizationStatus()
        let granted = await UserNotificationGateway.requestAuthorization()

        XCTAssertEqual(status, .denied)
        XCTAssertFalse(granted)
    }

    func testUnstubbedNotificationManagerDeliversNothing() async throws {
        let context = try NotificationManagerTestFactory.makeContext()
        let manager = DefaultNotificationManager(
            settingsService: InMemorySettingsService(),
            modelContainer: context.container,
            systemNotificationCenter: NotificationCenter()
        )
        // `notificationAuthorizationStatus` deliberately keeps its production default: this fails
        // the moment that default stops routing through the gateway. The other two seams only
        // record, so a regression is observed rather than delivered.
        let recorder = GatewayDeliveryRecorder()
        manager.addNotificationRequest = { recorder.addedIdentifiers.append($0.identifier) }
        manager.requestNotificationAuthorization = {
            recorder.authorizationRequests += 1
            return false
        }

        let status = await manager.notificationAuthorizationStatus()
        await manager.postAgentNotification(makeRequest(identifier: "conversation-1"))
        await manager.requestAuthorizationIfNeeded()

        XCTAssertEqual(status, .denied)
        XCTAssertTrue(recorder.addedIdentifiers.isEmpty)
        XCTAssertEqual(
            recorder.authorizationRequests,
            0,
            "Reporting `.denied` rather than `.notDetermined` is what keeps the system prompt from ever opening"
        )
    }

    func testUnstubbedScheduledFailureNotifierDeliversNothing() async {
        let notifier = ScheduledTaskDefinitionFailureNotifier(
            settingsService: InMemorySettingsService(),
            notificationCenter: NotificationCenter()
        )
        let recorder = GatewayDeliveryRecorder()
        notifier.addNotificationRequest = { recorder.addedIdentifiers.append($0.identifier) }
        notifier.requestNotificationAuthorization = {
            recorder.authorizationRequests += 1
            return false
        }

        let status = await notifier.notificationAuthorizationStatus()
        await notifier.post(makeRequest(identifier: "scheduled-task-definition:definition-1"))

        XCTAssertEqual(status, .denied)
        XCTAssertTrue(recorder.addedIdentifiers.isEmpty)
        XCTAssertEqual(recorder.authorizationRequests, 0)
    }

    private func makeRequest(identifier: String) -> UNNotificationRequest {
        UNNotificationRequest(identifier: identifier, content: UNMutableNotificationContent(), trigger: nil)
    }
}

@MainActor
private final class GatewayDeliveryRecorder {
    var addedIdentifiers: [String] = []
    var authorizationRequests = 0
}
