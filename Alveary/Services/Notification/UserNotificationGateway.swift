import AppKit
@preconcurrency import UserNotifications

/// The single chokepoint between Alveary and the machine-wide UserNotifications service.
///
/// App-hosted unit tests run inside the real `Alveary.app`, so every seam that reaches
/// `UNUserNotificationCenter.current()` by default puts a banner, a Dock badge, an authorization
/// dialog, or a sound on the developer's own desktop mid-run. Branching here suppresses all of
/// them no matter which construction site built the poster; the per-instance closure seams on
/// `DefaultNotificationManager` and `ScheduledTaskDefinitionFailureNotifier` only cover the
/// managers a test remembered to stub, and several suites do not.
enum UserNotificationGateway {
    /// `static let` rather than computed: `AppRuntimeProfile.current` is itself resolved once, and
    /// a constant makes the decision impossible to flip partway through a run.
    static let isSuppressed = AppRuntimeProfile.current.isHostedUnitTest

    /// `DefaultNotificationManager` and `ScheduledTaskDefinitionFailureNotifier` can race at launch
    /// and whichever asks first fixes what the user granted, so the option set lives here once
    /// instead of being repeated per poster where the two copies could drift apart.
    private static let authorizationOptions: UNAuthorizationOptions = [.alert, .sound, .badge]

    /// Reports `.denied` while suppressed, not `.notDetermined`, so `postAgentNotification` and
    /// `ScheduledTaskDefinitionFailureNotifier.post` short-circuit before they can join a shared
    /// authorization request, and `requestAuthorizationIfNeeded()` bails at its `.notDetermined`
    /// guard. It also makes unstubbed suites deterministic: they previously read whatever the
    /// developer's machine happened to have granted.
    static func authorizationStatus() async -> UNAuthorizationStatus {
        guard !isSuppressed else {
            return .denied
        }
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func requestAuthorization() async -> Bool {
        guard !isSuppressed else {
            return false
        }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: authorizationOptions)) ?? false
    }

    static func add(_ request: UNNotificationRequest) async {
        guard !isSuppressed else {
            return
        }
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        guard !isSuppressed else {
            return
        }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    static func setBadgeCount(_ count: Int) async {
        guard !isSuppressed else {
            return
        }
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }

    @MainActor
    static func playSound(named name: String) {
        guard !isSuppressed else {
            return
        }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
