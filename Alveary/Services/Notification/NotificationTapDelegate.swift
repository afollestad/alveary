import Foundation
@preconcurrency import UserNotifications

final class NotificationTapDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let router: NotificationRouter
    /// Bringing Alveary forward has one owner (`MainWindowPresenter`), because the app now
    /// survives its last window closing — a bare `NSApp.activate` would foreground a windowless
    /// app and leave the routed request undrained.
    private let activateAlveary: @MainActor () -> Void

    init(router: NotificationRouter, activateAlveary: @escaping @MainActor () -> Void) {
        self.router = router
        self.activateAlveary = activateAlveary
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

        guard let destination = Self.destination(
            actionIdentifier: response.actionIdentifier,
            userInfo: response.notification.request.content.userInfo
        ) else {
            return
        }

        let router = router
        let activateAlveary = activateAlveary
        Task { @MainActor in
            activateAlveary()
            switch destination {
            case .conversation(let conversationId):
                router.requestOpen(conversationId: conversationId)
            case .scheduledTaskDefinition(let definitionId):
                router.requestOpenScheduledTask(definitionId: definitionId)
            }
        }
    }

    static func destination(
        actionIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> NotificationTapDestination? {
        guard actionIdentifier == UNNotificationDefaultActionIdentifier else {
            return nil
        }
        if let definitionId = userInfo[NotificationUserInfoKey.scheduledTaskDefinitionId] as? String {
            return .scheduledTaskDefinition(definitionId)
        }
        if let conversationId = userInfo[NotificationUserInfoKey.conversationId] as? String {
            return .conversation(conversationId)
        }
        return nil
    }

    /// Extract the conversation id from a notification response payload. Returns `nil` when the
    /// response is not the default tap action or when the payload is missing the expected key.
    static func conversationId(
        actionIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> String? {
        guard case let .conversation(conversationId) = destination(
            actionIdentifier: actionIdentifier,
            userInfo: userInfo
        ) else {
            return nil
        }
        return conversationId
    }
}

enum NotificationTapDestination: Equatable, Sendable {
    case conversation(String)
    case scheduledTaskDefinition(String)
}
