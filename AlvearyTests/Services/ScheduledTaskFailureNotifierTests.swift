import Foundation
import XCTest

@testable import Alveary

@MainActor
final class ScheduledTaskFailureNotifierTests: XCTestCase {
    func testFailurePublishingAlwaysRefreshesBadgeAndPostsConversationStatus() {
        let manager = RecordingNotificationManager()
        let center = NotificationCenter()
        let statusExpectation = expectation(description: "conversation status published")
        let observer = center.addObserver(
            forName: .agentStatusChanged,
            object: nil,
            queue: nil
        ) { notification in
            if notification.userInfo?["conversationId"] as? String == "conversation" {
                statusExpectation.fulfill()
            }
        }
        defer { center.removeObserver(observer) }
        let notifier = ScheduledTaskFailureNotifier(
            notificationManager: manager,
            notificationCenter: center
        )

        notifier.publish(message: "Workspace preparation failed.", conversationID: "conversation")

        wait(for: [statusExpectation], timeout: 1)
        XCTAssertEqual(manager.refreshBadgeCountCalls, 1)
        XCTAssertEqual(manager.handleEventCalls.count, 1)
        XCTAssertEqual(manager.handleEventCalls.first?.conversationId, "conversation")
    }
}
