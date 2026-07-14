import Foundation

@MainActor
struct ScheduledTaskFailureNotifier {
    private let notificationManager: any NotificationManager
    private let notificationCenter: NotificationCenter

    init(
        notificationManager: any NotificationManager,
        notificationCenter: NotificationCenter = .default
    ) {
        self.notificationManager = notificationManager
        self.notificationCenter = notificationCenter
    }

    func publish(message: String, conversationID: String) {
        notificationManager.refreshBadgeCount()
        notificationCenter.post(
            name: .agentStatusChanged,
            object: nil,
            userInfo: ["conversationId": conversationID]
        )
        notificationManager.handleEvent(.error(message: message), conversationId: conversationID)
    }
}
