import AgentCLIKit
import XCTest

@testable import Alveary

extension AgentCLIKitEventMapperTests {
    func testExitedLifecycleWithExitCodeMapsToProviderExitStop() {
        let events = AgentCLIKitEventMapper().conversationEvents(
            from: envelope(.lifecycle(AgentLifecycleEvent(state: .exited, exitCode: 0)))
        )

        XCTAssertEqual(events, [.stop(message: "Claude Code exited unexpectedly (exit code 0)")])
        XCTAssertTrue(ConversationProviderExit.isDisplayMessage("Claude Code exited unexpectedly (exit code 0)"))
    }

    func testExitedLifecycleWithoutExitCodeMapsToPlainStop() {
        let events = AgentCLIKitEventMapper().conversationEvents(
            from: envelope(.lifecycle(AgentLifecycleEvent(state: .exited)))
        )

        XCTAssertEqual(events, [.stop(message: nil)])
    }

    func testFailedLifecycleWithExitCodeNamesProviderAndCode() {
        let events = AgentCLIKitEventMapper().conversationEvents(
            from: envelope(.lifecycle(AgentLifecycleEvent(state: .failed, exitCode: 137)), providerId: .codex)
        )

        XCTAssertEqual(events, [.error(message: "Codex failed (exit code 137)")])
    }
}
