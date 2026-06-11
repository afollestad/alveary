import AgentCLIKit
import XCTest

@testable import Alveary

extension AgentCLIKitEventMapperTests {
    func testMapsFailedTaskNotificationToFailedSubAgentCompletionAndResult() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.task(AgentTaskEvent(
            id: "agent-tool-1",
            phase: .notification,
            description: "Agent failed",
            toolUses: 2,
            totalTokens: 1234,
            durationMs: 5678,
            status: "failed",
            metadata: ["result": .string("Failure details")]
        ))))

        XCTAssertEqual(events, [
            .subAgentCompleted(
                toolUseId: "agent-tool-1",
                status: "failed",
                toolUses: 2,
                totalTokens: 1234,
                durationMs: 5678
            ),
            .toolResult(
                id: "agent-tool-1",
                output: "Failure details",
                isError: true,
                parentToolUseId: nil,
                metadata: ToolResultMetadata(
                    stderr: nil,
                    interrupted: false,
                    isImage: false,
                    noOutputExpected: false
                )
            )
        ])
    }

    func testMapsInterruptedTaskNotificationToInterruptedSubAgentCompletionAndResult() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.task(AgentTaskEvent(
            id: "agent-tool-1",
            phase: .notification,
            status: "interrupted",
            metadata: ["result": .string("Partial result")]
        ))))

        XCTAssertEqual(events, [
            .subAgentCompleted(
                toolUseId: "agent-tool-1",
                status: "interrupted",
                toolUses: 0,
                totalTokens: 0,
                durationMs: 0
            ),
            .toolResult(
                id: "agent-tool-1",
                output: "Partial result",
                isError: false,
                parentToolUseId: nil,
                metadata: ToolResultMetadata(
                    stderr: nil,
                    interrupted: true,
                    isImage: false,
                    noOutputExpected: false
                )
            )
        ])
    }
}
