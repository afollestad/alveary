import XCTest

@testable import Alveary

@MainActor
extension DiffViewerViewModelTests {
    // Posts a signal-less `.agentStatusChanged` immediately followed by a signal-carrying post and
    // waits for the latter's rescan to finish. Because the notification bus delivers synchronously
    // on the main queue, the no-signal post's observer runs (and short-circuits) strictly before
    // the signal post's Task is spawned — so observing `statusCallCount == initialStatusCalls + 1`
    // after fulfillment proves the no-signal post did not trigger a rescan.
    func testAgentStatusChangedGatingRespectsSignalKey() async throws {
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(statusResults: Array(repeating: .success([]), count: 6))
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: ["conv-1"]
        )
        let initialStatusCalls = await fixture.gitService.statusCallCount()

        let rescanExpectation = expectation(description: "signal-carrying post triggers rescan")
        await fixture.gitService.setOnStatus { rescanExpectation.fulfill() }

        // Mimic `DefaultNotificationManager.setConversationUnread` — no `signal` key.
        NotificationCenter.default.post(
            name: .agentStatusChanged,
            object: nil,
            userInfo: ["conversationId": "conv-1"]
        )
        // Mimic `DefaultAgentsManager.updateStatus` — carries an `ActivitySignal`.
        NotificationCenter.default.post(
            name: .agentStatusChanged,
            object: nil,
            userInfo: ["conversationId": "conv-1", "signal": ActivitySignal.idle]
        )

        await fulfillment(of: [rescanExpectation], timeout: 1.0)

        let finalStatusCalls = await fixture.gitService.statusCallCount()
        XCTAssertEqual(
            finalStatusCalls,
            initialStatusCalls + 1,
            "only the signal-carrying post should trigger a rescan"
        )
    }
}
