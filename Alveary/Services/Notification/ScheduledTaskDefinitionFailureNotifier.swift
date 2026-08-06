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
    /// Shared so concurrent failures join one system prompt instead of being dropped.
    private var authorizationRequestTask: Task<Bool, Never>?

    var onPostNotification: NotificationPoster?
    var playInAppSound: @MainActor (String) -> Void = { name in
        NSSound(named: NSSound.Name(name))?.play()
    }
    var notificationAuthorizationStatus: @MainActor () async -> UNAuthorizationStatus = {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    /// Matches `DefaultNotificationManager`'s option set. These two can race at launch, and
    /// whichever asks first fixes what the user is granted — a narrower set here would silently
    /// cost the badge permission.
    var requestNotificationAuthorization: @MainActor () async -> Bool = {
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: options)) ?? false
    }
    var addNotificationRequest: @MainActor (UNNotificationRequest) async -> Void = { request in
        try? await UNUserNotificationCenter.current().add(request)
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
            await post(request)
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

extension ScheduledTaskDefinitionFailureNotifier {
    func post(_ request: UNNotificationRequest) async {
        switch await notificationAuthorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            await addNotificationRequest(request)
        case .notDetermined:
            // Failures can arrive in a batch while the prompt is up; a per-launch "already asked"
            // flag delivered only the first and silently dropped the rest.
            guard await sharedAuthorizationRequest() else {
                return
            }
            await addNotificationRequest(request)
        case .denied:
            return
        @unknown default:
            return
        }
    }

    private func sharedAuthorizationRequest() async -> Bool {
        if let authorizationRequestTask {
            return await authorizationRequestTask.value
        }

        let request = requestNotificationAuthorization
        let task = Task<Bool, Never> { @MainActor in
            await request()
        }
        authorizationRequestTask = task
        return await task.value
    }
}
