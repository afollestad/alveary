import Foundation
import UserNotifications
import XCTest

@testable import Alveary

@MainActor
extension ScheduledDefinitionFailureNotifierTests {
    func testBatchedFailuresDuringAPendingPromptAllDeliver() async throws {
        let recorder = NotifierAuthorizationRecorder()
        let notifier = makeAuthorizationNotifier(status: .notDetermined, recorder: recorder)
        let gate = NotifierAuthorizationGate()
        notifier.requestNotificationAuthorization = {
            recorder.requestCount += 1
            return await gate.wait()
        }

        // Scheduled definitions can fail in a batch; the old per-launch flag kept only the first.
        let first = Task { @MainActor in await notifier.post(makeRequest(identifier: "first")) }
        let second = Task { @MainActor in await notifier.post(makeRequest(identifier: "second")) }
        try await waitUntilRequested(recorder)
        gate.resume(granted: true)
        await first.value
        await second.value

        XCTAssertEqual(recorder.requestCount, 1, "Concurrent failures must share one system prompt")
        XCTAssertEqual(Set(recorder.addedIdentifiers), ["first", "second"])
    }

    func testDeniedAuthorizationDeliversNothingAndNeverPrompts() async {
        let recorder = NotifierAuthorizationRecorder()
        let notifier = makeAuthorizationNotifier(status: .denied, recorder: recorder)

        await notifier.post(makeRequest(identifier: "denied"))

        XCTAssertTrue(recorder.addedIdentifiers.isEmpty)
        XCTAssertEqual(recorder.requestCount, 0)
    }

    func testDeclinedPromptDeliversNothing() async {
        let recorder = NotifierAuthorizationRecorder()
        let notifier = makeAuthorizationNotifier(status: .notDetermined, recorder: recorder)
        notifier.requestNotificationAuthorization = {
            recorder.requestCount += 1
            return false
        }

        await notifier.post(makeRequest(identifier: "declined"))

        XCTAssertEqual(recorder.requestCount, 1)
        XCTAssertTrue(recorder.addedIdentifiers.isEmpty)
    }

    private func makeAuthorizationNotifier(
        status: UNAuthorizationStatus,
        recorder: NotifierAuthorizationRecorder
    ) -> ScheduledTaskDefinitionFailureNotifier {
        let notifier = ScheduledTaskDefinitionFailureNotifier(
            settingsService: InMemorySettingsService(),
            notificationCenter: NotificationCenter()
        )
        notifier.notificationAuthorizationStatus = { status }
        notifier.requestNotificationAuthorization = {
            recorder.requestCount += 1
            return true
        }
        notifier.addNotificationRequest = { request in
            recorder.addedIdentifiers.append(request.identifier)
        }
        return notifier
    }

    private func makeRequest(identifier: String) -> UNNotificationRequest {
        UNNotificationRequest(identifier: identifier, content: UNMutableNotificationContent(), trigger: nil)
    }

    private func waitUntilRequested(_ recorder: NotifierAuthorizationRecorder) async throws {
        for _ in 0..<200 where recorder.requestCount == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(recorder.requestCount, 1)
    }
}

@MainActor
private final class NotifierAuthorizationRecorder {
    var requestCount = 0
    var addedIdentifiers: [String] = []
}

/// Holds the prompt open so a second failure can arrive while it is still pending.
@MainActor
private final class NotifierAuthorizationGate {
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
