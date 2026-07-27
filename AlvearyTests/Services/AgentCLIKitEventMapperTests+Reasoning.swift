import AgentCLIKit
import XCTest

@testable import Alveary

extension AgentCLIKitEventMapperTests {
    func testMapsReasoningToThinking() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.reasoning(AgentReasoningEvent(
            text: "Thinking",
            metadata: ["parent_tool_use_id": .string("parent-1")]
        ))))

        XCTAssertEqual(events, [
            .thinking(content: "Thinking", parentToolUseId: "parent-1")
        ])
    }

    func testMapsReasoningSectionBreakToThinking() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.reasoning(AgentReasoningEvent(
            text: "\n\n",
            metadata: [
                "codex_reasoning_kind": .string("summary"),
                "codex_reasoning_index": .number(1)
            ]
        ))))

        XCTAssertEqual(events, [
            .thinking(content: "\n\n", parentToolUseId: nil)
        ])
    }

    func testDropsCompletedCodexReasoningSnapshot() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.reasoning(AgentReasoningEvent(
            text: "Thinking",
            metadata: [
                "codex_item_phase": .string("completed"),
                "codex_item_type": .string("reasoning")
            ]
        ))))

        XCTAssertEqual(events, [])
    }
}
