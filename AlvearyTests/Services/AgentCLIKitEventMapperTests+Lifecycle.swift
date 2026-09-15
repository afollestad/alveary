import AgentCLIKit
import XCTest

@testable import Alveary

extension AgentCLIKitEventMapperTests {
    func testExitedLifecycleWithExitCodeMapsToHarnessExitStop() {
        let events = AgentCLIKitEventMapper().conversationEvents(
            from: envelope(.lifecycle(AgentLifecycleEvent(state: .exited, exitCode: 0)))
        )

        XCTAssertEqual(events, [.stop(message: "Claude Code exited unexpectedly (exit code 0)")])
        XCTAssertTrue(ConversationHarnessExit.isDisplayMessage("Claude Code exited unexpectedly (exit code 0)"))
    }

    func testExitedLifecycleWithoutExitCodeMapsToPlainStop() {
        let events = AgentCLIKitEventMapper().conversationEvents(
            from: envelope(.lifecycle(AgentLifecycleEvent(state: .exited)))
        )

        XCTAssertEqual(events, [.stop(message: nil)])
    }

    func testFailedLifecycleWithExitCodeNamesHarnessAndCode() {
        let events = AgentCLIKitEventMapper().conversationEvents(
            from: envelope(.lifecycle(AgentLifecycleEvent(state: .failed, exitCode: 137)), harnessId: .codex)
        )

        XCTAssertEqual(events, [.error(message: "Codex failed (exit code 137)")])
    }
}
