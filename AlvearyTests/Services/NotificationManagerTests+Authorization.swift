import Foundation
import UserNotifications
import XCTest

@testable import Alveary

@MainActor
final class NotificationManagerAuthorizationTests: XCTestCase {
    func testNotificationsArrivingDuringAPendingPromptAllDeliver() async throws {
        let recorder = AuthorizationRecorder()
        let manager = try makeManager(status: .notDetermined, recorder: recorder)
        let gate = AuthorizationGate()
        manager.requestNotificationAuthorization = {
            recorder.requestCount += 1
            return await gate.wait()
        }

        // Two notifications race the same prompt; the old per-launch flag dropped the second.
        let firstRequest = makeRequest(identifier: "first")
        let secondRequest = makeRequest(identifier: "second")
        let first = Task { @MainActor in await manager.postAgentNotification(firstRequest) }
        let second = Task { @MainActor in await manager.postAgentNotification(secondRequest) }
        try await waitUntilRequested(recorder)
        gate.resume(granted: true)
        await first.value
        await second.value

        XCTAssertEqual(recorder.requestCount, 1, "Concurrent posts must share one system prompt")
        XCTAssertEqual(Set(recorder.addedIdentifiers), ["first", "second"])
    }

    func testDeniedAuthorizationDeliversNothingAndNeverPrompts() async throws {
        let recorder = AuthorizationRecorder()
        let manager = try makeManager(status: .denied, recorder: recorder)

        await manager.postAgentNotification(makeRequest(identifier: "denied"))

        XCTAssertTrue(recorder.addedIdentifiers.isEmpty)
        XCTAssertEqual(recorder.requestCount, 0)
    }

    func testDeclinedPromptDeliversNothing() async throws {
        let recorder = AuthorizationRecorder()
        let manager = try makeManager(status: .notDetermined, recorder: recorder)
        manager.requestNotificationAuthorization = {
            recorder.requestCount += 1
            return false
        }

        await manager.postAgentNotification(makeRequest(identifier: "declined"))

        XCTAssertEqual(recorder.requestCount, 1)
        XCTAssertTrue(recorder.addedIdentifiers.isEmpty)
    }

    func testRequestAuthorizationIfNeededPromptsOnceAndIsIdempotent() async throws {
        let recorder = AuthorizationRecorder()
        let manager = try makeManager(status: .notDetermined, recorder: recorder)

        await manager.requestAuthorizationIfNeeded()
        await manager.requestAuthorizationIfNeeded()

        XCTAssertEqual(recorder.requestCount, 1)
    }

    func testRequestAuthorizationIfNeededRespectsSettingsAndExistingStatus() async throws {
        let disabledRecorder = AuthorizationRecorder()
        let disabled = try makeManager(
            status: .notDetermined,
            recorder: disabledRecorder,
            notifications: NotificationSettings(enabled: false)
        )
        await disabled.requestAuthorizationIfNeeded()
        XCTAssertEqual(disabledRecorder.requestCount, 0)

        let osDisabledRecorder = AuthorizationRecorder()
        let osDisabled = try makeManager(
            status: .notDetermined,
            recorder: osDisabledRecorder,
            notifications: NotificationSettings(enabled: true, osNotifications: false)
        )
        await osDisabled.requestAuthorizationIfNeeded()
        XCTAssertEqual(osDisabledRecorder.requestCount, 0)

        let authorizedRecorder = AuthorizationRecorder()
        let authorized = try makeManager(status: .authorized, recorder: authorizedRecorder)
        await authorized.requestAuthorizationIfNeeded()
        XCTAssertEqual(authorizedRecorder.requestCount, 0)
    }

    private func makeManager(
        status: UNAuthorizationStatus,
        recorder: AuthorizationRecorder,
        notifications: NotificationSettings = NotificationSettings(enabled: true)
    ) throws -> DefaultNotificationManager {
        let context = try NotificationManagerTestFactory.makeContext()
        var settings = AppSettings()
        settings.notifications = notifications
        let manager = DefaultNotificationManager(
            settingsService: InMemorySettingsService(current: settings),
            modelContainer: context.container,
            systemNotificationCenter: NotificationCenter()
        )
        manager.notificationAuthorizationStatus = { status }
        manager.requestNotificationAuthorization = {
            recorder.requestCount += 1
            return true
        }
        manager.addNotificationRequest = { request in
            recorder.addedIdentifiers.append(request.identifier)
        }
        return manager
    }

    private func makeRequest(identifier: String) -> UNNotificationRequest {
        UNNotificationRequest(identifier: identifier, content: UNMutableNotificationContent(), trigger: nil)
    }

    private func waitUntilRequested(_ recorder: AuthorizationRecorder) async throws {
        for _ in 0..<200 where recorder.requestCount == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(recorder.requestCount, 1)
    }
}

@MainActor
private final class AuthorizationRecorder {
    var requestCount = 0
    var addedIdentifiers: [String] = []
}

/// Holds the prompt open so a second notification can arrive while it is still pending.
@MainActor
private final class AuthorizationGate {
    private var continuations: [CheckedContinuation<Bool, Never>] = []
    private var resolved: Bool?

    func wait() async -> Bool {
        if let resolved {
            return resolved
        }
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resume(granted: Bool) {
        resolved = granted
        let pending = continuations
        continuations = []
        for continuation in pending {
            continuation.resume(returning: granted)
        }
    }
}
