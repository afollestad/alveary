import AppKit
import Foundation
@preconcurrency import UserNotifications

final class NotificationTapDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let router: NotificationRouter

    init(router: NotificationRouter) {
        self.router = router
        super.init()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard let conversationId = Self.conversationId(
            actionIdentifier: response.actionIdentifier,
            userInfo: response.notification.request.content.userInfo
        ) else {
            return
        }

        let router = router
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            router.requestOpen(conversationId: conversationId)
        }
    }

    /// Extract the conversation id from a notification response payload. Returns `nil` when the
    /// response is not the default tap action or when the payload is missing the expected key.
    static func conversationId(
        actionIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> String? {
        guard actionIdentifier == UNNotificationDefaultActionIdentifier else {
            return nil
        }
        return userInfo[NotificationUserInfoKey.conversationId] as? String
    }
}
