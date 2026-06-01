import AgentCLIKit
import XCTest

@testable import Alveary

extension AgentCLIKitEventMapperTests {
    func testMapsCompletedTaskWithSummaryOnlyToSubAgentCompletion() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.task(AgentTaskEvent(
            id: "agent-tool-1",
            phase: .notification,
            description: "Map project structure",
            toolUses: 1,
            totalTokens: 200,
            durationMs: 300,
            status: "completed",
            metadata: ["summary": .string("Map project structure")]
        ))))

        XCTAssertEqual(events, [
            .subAgentCompleted(
                toolUseId: "agent-tool-1",
                status: "completed",
                toolUses: 1,
                totalTokens: 200,
                durationMs: 300
            )
        ])
    }

    func testMapsRawTaskNotificationWithoutResultToSubAgentCompletionOnly() throws {
        let taskNotification = """
        <task-notification>
        <task-id>agent-task-1</task-id>
        <tool-use-id>agent-tool-1</tool-use-id>
        <output-file>/tmp/agent-task-1.output</output-file>
        <status>completed</status>
        <summary>Map project structure</summary>
        <usage><total_tokens>200</total_tokens><tool_uses>1</tool_uses><duration_ms>300</duration_ms></usage>
        </task-notification>
        """
        let lineData = try JSONSerialization.data(withJSONObject: [
            "type": "user",
            "origin": ["kind": "task-notification"],
            "message": [
                "role": "user",
                "content": taskNotification
            ]
        ] as [String: Any])
        let line = try XCTUnwrap(String(data: lineData, encoding: .utf8))
        let events = try conversationEvents(from: line)

        XCTAssertEqual(events, [
            .subAgentCompleted(
                toolUseId: "agent-tool-1",
                status: "completed",
                toolUses: 1,
                totalTokens: 200,
                durationMs: 300
            )
        ])
    }

    func testMapsQueuedTaskNotificationWithoutResultToSubAgentCompletionOnly() throws {
        let taskNotification = """
        <task-notification>
        <task-id>agent-task-1</task-id>
        <tool-use-id>agent-tool-1</tool-use-id>
        <output-file>/tmp/agent-task-1.output</output-file>
        <status>completed</status>
        <summary>Map project structure</summary>
        <usage><total_tokens>200</total_tokens><tool_uses>1</tool_uses><duration_ms>300</duration_ms></usage>
        </task-notification>
        """
        let lineData = try JSONSerialization.data(withJSONObject: [
            "type": "attachment",
            "sessionId": "session-123",
            "attachment": [
                "type": "queued_command",
                "commandMode": "task-notification",
                "prompt": taskNotification
            ]
        ] as [String: Any])
        let line = try XCTUnwrap(String(data: lineData, encoding: .utf8))
        let events = try conversationEvents(from: line)

        XCTAssertEqual(events, [
            .subAgentCompleted(
                toolUseId: "agent-tool-1",
                status: "completed",
                toolUses: 1,
                totalTokens: 200,
                durationMs: 300
            )
        ])
    }

    private func conversationEvents(from line: String) throws -> [ConversationEvent] {
        try ClaudeStreamDecoder().decodeLine(line).flatMap {
            AgentCLIKitEventMapper().conversationEvents(from: envelope($0))
        }
    }

    private func envelope(_ event: AgentCLIKit.AgentEvent) -> AgentCLIKit.AgentEventEnvelope {
        AgentCLIKit.AgentEventEnvelope(
            generation: 1,
            index: 0,
            providerId: .claude,
            conversationId: "conversation",
            providerSessionId: nil,
            source: .stdout,
            event: event,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}
