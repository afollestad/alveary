import AppKit
import Foundation
@preconcurrency import UserNotifications

extension NotificationUserInfoKey {
    static let scheduledTaskDefinitionId = "scheduledTaskDefinitionId"
}

@MainActor
final class ScheduledTaskDefinitionFailureNotifier {
    static let notificationIdentifierPrefix = "scheduled-task-definition:"
    static let notificationTitle = "Scheduled task needs attention"

    typealias NotificationPoster = @MainActor (UNNotificationRequest) -> Void

    private let settingsService: any SettingsService
    private let notificationCenter: NotificationCenter
    private var hasRequestedAuthorizationThisLaunch = false

    var onPostNotification: NotificationPoster?
    var playInAppSound: @MainActor (String) -> Void = { name in
        NSSound(named: NSSound.Name(name))?.play()
    }

    init(
        settingsService: any SettingsService,
        notificationCenter: NotificationCenter = .default
    ) {
        self.settingsService = settingsService
        self.notificationCenter = notificationCenter
    }

    func publish(definitionID: String, title: String, reason: String) {
        notificationCenter.postScheduledTasksChanged(
            object: self,
            definitionID: definitionID
        )
        let settings = settingsService.current.notifications
        guard settings.enabled else {
            return
        }
        if settings.sound, !settings.osNotifications {
            playInAppSound(settings.soundName ?? NotificationSettings.defaultSoundName)
        }
        guard settings.osNotifications else {
            return
        }
        let request = makeNotificationRequest(
            definitionID: definitionID,
            title: title,
            reason: reason,
            playSound: settings.sound
        )
        if let onPostNotification {
            onPostNotification(request)
            return
        }
        Task { @MainActor in
            await post(request, with: UNUserNotificationCenter.current())
        }
    }

    func makeNotificationRequest(
        definitionID: String,
        title: String,
        reason: String,
        playSound: Bool
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = Self.notificationTitle
        content.body = "\"\(title)\" was paused: \(reason)"
        content.userInfo = [NotificationUserInfoKey.scheduledTaskDefinitionId: definitionID]
        if playSound {
            content.sound = .default
        }
        return UNNotificationRequest(
            identifier: Self.notificationIdentifierPrefix + definitionID,
            content: content,
            trigger: nil
        )
    }
}

private extension ScheduledTaskDefinitionFailureNotifier {
    func post(_ request: UNNotificationRequest, with center: UNUserNotificationCenter) async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            try? await center.add(request)
        case .notDetermined:
            guard !hasRequestedAuthorizationThisLaunch else {
                return
            }
            hasRequestedAuthorizationThisLaunch = true
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else {
                return
            }
            try? await center.add(request)
        case .denied:
            return
        @unknown default:
            return
        }
    }
}
