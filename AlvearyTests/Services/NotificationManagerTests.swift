import XCTest

@testable import Alveary

@MainActor
final class NotificationManagerTests: XCTestCase {
    func testFocusedStopEventPlaysInAppSoundOnly() {
        let service = InMemorySettingsService()
        service.update { $0.notifications.soundName = "Purr" }
        let spy = NotificationSpy()
        let manager = makeManager(
            settingsService: service,
            isFocused: true,
            spy: spy
        )

        manager.handleEvent(.stop(message: nil), providerName: "Claude", threadName: "Thread")

        XCTAssertEqual(spy.playedSounds, ["Purr"])
        XCTAssertTrue(spy.postedNotifications.isEmpty)
    }

    func testUnfocusedCompletionEventPostsOSNotificationOnly() {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let manager = makeManager(
            settingsService: service,
            isFocused: false,
            spy: spy
        )

        manager.handleEvent(
            .tokens(
                input: 1,
                output: 2,
                cacheRead: 0,
                isError: false,
                stopReason: "end_turn",
                durationMs: 100,
                costUsd: 0.01,
                permissionDenials: []
            ),
            providerName: "Claude",
            threadName: "Thread"
        )

        XCTAssertTrue(spy.playedSounds.isEmpty)
        XCTAssertEqual(
            spy.postedNotifications,
            [PostedNotification(providerName: "Claude", threadName: "Thread", message: "Your agent has finished working", playSound: true)]
        )
    }

    func testPermissionDenialRoutesToPermissionMessage() {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let manager = makeManager(
            settingsService: service,
            isFocused: false,
            spy: spy
        )

        manager.handleEvent(
            .tokens(
                input: 1,
                output: 2,
                cacheRead: 0,
                isError: true,
                stopReason: "permission denied",
                durationMs: 100,
                costUsd: 0.01,
                permissionDenials: [PermissionDenialSummary(toolName: "Edit", toolUseId: "tool-1")]
            ),
            providerName: "Claude",
            threadName: "Thread"
        )

        XCTAssertTrue(spy.playedSounds.isEmpty)
        XCTAssertEqual(spy.postedNotifications.first?.message, "Your agent needs permission")
    }

    func testDisabledNotificationsSuppressAllOutputs() {
        let service = InMemorySettingsService()
        service.update { $0.notifications.enabled = false }
        let spy = NotificationSpy()
        let manager = makeManager(
            settingsService: service,
            isFocused: false,
            spy: spy
        )

        manager.handleEvent(.error(message: "Boom"), providerName: "Claude", threadName: nil)

        XCTAssertTrue(spy.playedSounds.isEmpty)
        XCTAssertTrue(spy.postedNotifications.isEmpty)
    }

    func testUnfocusedWithoutOSNotificationsDoesNothing() {
        let service = InMemorySettingsService()
        service.update { $0.notifications.osNotifications = false }
        let spy = NotificationSpy()
        let manager = makeManager(
            settingsService: service,
            isFocused: false,
            spy: spy
        )

        manager.handleEvent(.notification(type: "idle_prompt", message: nil), providerName: "Claude", threadName: nil)

        XCTAssertTrue(spy.playedSounds.isEmpty)
        XCTAssertTrue(spy.postedNotifications.isEmpty)
    }

    func testIgnoresNonTerminalEvents() {
        let service = InMemorySettingsService()
        let spy = NotificationSpy()
        let manager = makeManager(
            settingsService: service,
            isFocused: true,
            spy: spy
        )

        manager.handleEvent(.message(role: "assistant", content: "Working", parentToolUseId: nil), providerName: "Claude", threadName: nil)

        XCTAssertTrue(spy.playedSounds.isEmpty)
        XCTAssertTrue(spy.postedNotifications.isEmpty)
    }

    private func makeManager(
        settingsService: InMemorySettingsService,
        isFocused: Bool,
        spy: NotificationSpy
    ) -> DefaultNotificationManager {
        let manager = DefaultNotificationManager(settingsService: settingsService)
        manager.isFocused = { isFocused }
        manager.playInAppSound = { spy.playedSounds.append($0) }
        manager.onPostNotification = { providerName, threadName, message, playSound in
            spy.postedNotifications.append(
                PostedNotification(
                    providerName: providerName,
                    threadName: threadName,
                    message: message,
                    playSound: playSound
                )
            )
        }
        return manager
    }
}

private struct PostedNotification: Equatable {
    let providerName: String
    let threadName: String?
    let message: String
    let playSound: Bool
}

private final class NotificationSpy {
    var playedSounds: [String] = []
    var postedNotifications: [PostedNotification] = []
}
