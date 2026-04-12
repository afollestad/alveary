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
        guard settings.notifications.enabled,
              let message = notificationMessage(for: event) else {
            return
        }

        if isFocused() {
            playInAppSoundIfNeeded(settings: settings)
            return
        }

        postNotificationIfAllowed(
            providerName: providerName,
            threadName: threadName,
            message: message,
            settings: settings
        )
    }

    private func notificationMessage(for event: ConversationEvent) -> String? {
        switch event {
        case .stop(let stopMessage):
            return stopMessage ?? "Your agent has finished working"
        case .notification(let type, let notificationText):
            return notificationMessage(for: type, text: notificationText)
        case .tokens(_, _, _, let isError, let stopReason, _, _, let permissionDenials):
            return tokenNotificationMessage(
                isError: isError,
                stopReason: stopReason,
                permissionDenials: permissionDenials
            )
        case .error(let errorMessage):
            return errorMessage.isEmpty ? "Your agent encountered an error" : errorMessage
        default:
            return nil
        }
    }

    private func notificationMessage(for type: String, text: String?) -> String? {
        switch type {
        case "idle_prompt":
            return text ?? "Your agent is waiting for input"
        case "permission_prompt":
            return text ?? "Your agent needs permission"
        default:
            return nil
        }
    }

    private func tokenNotificationMessage(
        isError: Bool,
        stopReason: String?,
        permissionDenials: [PermissionDenialSummary]
    ) -> String {
        if !permissionDenials.isEmpty {
            return "Your agent needs permission"
        }

        if isError {
            let trimmedStopReason = stopReason?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedStopReason.flatMap { $0.isEmpty ? nil : $0 } ?? "Your agent encountered an error"
        }

        return "Your agent has finished working"
    }

    private func playInAppSoundIfNeeded(settings: AppSettings) {
        guard settings.notifications.sound else {
            return
        }

        playInAppSound(settings.notifications.soundName ?? NotificationSettings.defaultSoundName)
    }

    private func postNotificationIfAllowed(
        providerName: String,
        threadName: String?,
        message: String,
        settings: AppSettings
    ) {
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
        let request = makeNotificationRequest(
            providerName: providerName,
            threadName: threadName,
            message: message,
            playSound: playSound
        )

        Task { @MainActor in
            await postAgentNotification(request, with: center)
        }
    }

    func postAgentNotification(_ request: UNNotificationRequest, with center: UNUserNotificationCenter) async {
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

    func makeNotificationRequest(
        providerName: String,
        threadName: String?,
        message: String,
        playSound: Bool
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = threadName.map { "\(providerName) - \($0)" } ?? providerName
        content.body = message
        if playSound {
            content.sound = .default
        }

        return UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
    }
}
