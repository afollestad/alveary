import AppKit
@preconcurrency import UserNotifications

@MainActor
final class DefaultNotificationManager: NotificationManager {
    private let settingsService: any SettingsService
    private var hasRequestedAuthorizationThisLaunch = false

    var isFocused: @MainActor () -> Bool = { NSApp.isActive }
    var playInAppSound: @MainActor (String) -> Void = { name in
        NSSound(named: NSSound.Name(name))?.play()
    }
    var onPostNotification: (@MainActor (_ providerName: String, _ threadName: String?, _ message: String, _ playSound: Bool) -> Void)?

    init(settingsService: any SettingsService) {
        self.settingsService = settingsService
    }

    func handleEvent(_ event: ConversationEvent, providerName: String, threadName: String?) {
        let settings = settingsService.current
        guard settings.notifications.enabled else {
            return
        }

        let message: String
        switch event {
        case .stop(let stopMessage):
            message = stopMessage ?? "Your agent has finished working"
        case .notification(let type, let notificationText):
            let notificationMessage: String
            switch type {
            case "idle_prompt":
                notificationMessage = notificationText ?? "Your agent is waiting for input"
            case "permission_prompt":
                notificationMessage = notificationText ?? "Your agent needs permission"
            default:
                return
            }
            message = notificationMessage
        case .tokens(_, _, _, let isError, let stopReason, _, _, let permissionDenials):
            if !permissionDenials.isEmpty {
                message = "Your agent needs permission"
            } else if isError {
                let trimmedStopReason = stopReason?.trimmingCharacters(in: .whitespacesAndNewlines)
                message = trimmedStopReason.flatMap { $0.isEmpty ? nil : $0 } ?? "Your agent encountered an error"
            } else {
                message = "Your agent has finished working"
            }
        case .error(let errorMessage):
            message = errorMessage.isEmpty ? "Your agent encountered an error" : errorMessage
        default:
            return
        }

        if isFocused() {
            if settings.notifications.sound {
                playInAppSound(settings.notifications.soundName ?? NotificationSettings.defaultSoundName)
            }
            return
        }

        guard settings.notifications.osNotifications else {
            return
        }

        if let onPostNotification {
            onPostNotification(providerName, threadName, message, settings.notifications.sound)
        } else {
            postAgentNotification(
                providerName: providerName,
                threadName: threadName,
                message: message,
                playSound: settings.notifications.sound
            )
        }
    }

    private func postAgentNotification(
        providerName: String,
        threadName: String?,
        message: String,
        playSound: Bool
    ) {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = threadName.map { "\(providerName) - \($0)" } ?? providerName
        content.body = message
        if playSound {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        let enqueueRequest = {
            center.add(request)
        }

        center.getNotificationSettings { settings in
            Task { @MainActor in
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    enqueueRequest()
                case .notDetermined:
                    guard !self.hasRequestedAuthorizationThisLaunch else {
                        return
                    }
                    self.hasRequestedAuthorizationThisLaunch = true
                    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        guard granted else {
                            return
                        }
                        enqueueRequest()
                    }
                case .denied:
                    return
                @unknown default:
                    return
                }
            }
        }
    }
}
