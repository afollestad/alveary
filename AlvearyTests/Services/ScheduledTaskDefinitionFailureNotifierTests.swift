import UserNotifications
import XCTest

@testable import Alveary

@MainActor
final class ScheduledDefinitionFailureNotifierTests: XCTestCase {
    func testDefinitionFailureUsesNamespacedIdentifierAndDefinitionRouteWithoutBadgePayload() throws {
        let notifier = ScheduledTaskDefinitionFailureNotifier(settingsService: InMemorySettingsService())

        let request = notifier.makeNotificationRequest(
            definitionID: "definition-7",
            title: "Nightly audit",
            reason: "Provider unavailable.",
            playSound: true
        )

        XCTAssertEqual(request.identifier, "scheduled-task-definition:definition-7")
        XCTAssertEqual(request.content.title, "Scheduled task needs attention")
        XCTAssertEqual(request.content.body, "\"Nightly audit\" was paused: Provider unavailable.")
        XCTAssertEqual(
            request.content.userInfo[NotificationUserInfoKey.scheduledTaskDefinitionId] as? String,
            "definition-7"
        )
        XCTAssertNil(request.content.userInfo[NotificationUserInfoKey.conversationId])
        XCTAssertNotNil(request.content.sound)
    }

    func testPublishUsesInjectedPosterAndDoesNotTouchConversationNotificationManager() {
        let notificationCenter = NotificationCenter()
        let notifier = ScheduledTaskDefinitionFailureNotifier(
            settingsService: InMemorySettingsService(),
            notificationCenter: notificationCenter
        )
        var requests: [UNNotificationRequest] = []
        let definitionChanges = ScheduledTaskDefinitionChangeRecorder()
        notifier.onPostNotification = { requests.append($0) }
        let observer = notificationCenter.addObserver(
            forName: .scheduledTasksChanged,
            object: nil,
            queue: .main
        ) { notification in
            definitionChanges.record(notification.userInfo?["definitionID"] as? String ?? "")
        }
        defer { notificationCenter.removeObserver(observer) }

        notifier.publish(
            definitionID: "definition-8",
            title: "Weekly report",
            reason: "Folder access changed."
        )

        XCTAssertEqual(requests.map(\.identifier), ["scheduled-task-definition:definition-8"])
        XCTAssertEqual(definitionChanges.values, ["definition-8"])
    }
}

private final class ScheduledTaskDefinitionChangeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var definitionIDs: [String] = []

    var values: [String] {
        lock.withLock { definitionIDs }
    }

    func record(_ definitionID: String) {
        lock.withLock { definitionIDs.append(definitionID) }
    }
}
