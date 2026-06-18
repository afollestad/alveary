import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

extension AgentCLIKitEventMapperTests {
    func testMapsTypedSubAgentStartToMarkedAgentToolCall() throws {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(
            .subAgent(AgentSubAgentEvent(
                id: "spawn-1",
                phase: .started,
                description: "Review the diff",
                prompt: "Review the diff",
                agentType: "codex",
                input: .object([
                    "codex_collab_tool": .string("spawnAgent")
                ]),
                parentToolUseId: "parent-1",
                callerAgent: "root"
            )),
            providerId: .codex
        ))

        XCTAssertEqual(events.count, 1)
        guard case .toolCall(let id, let name, let input, let parentToolUseId, let callerAgent) = try XCTUnwrap(events.first) else {
            return XCTFail("Expected a tool call")
        }
        XCTAssertEqual(id, "spawn-1")
        XCTAssertEqual(name, "Agent")
        XCTAssertEqual(parentToolUseId, "parent-1")
        XCTAssertEqual(callerAgent, "root")

        let json = try Self.jsonObject(from: input)
        XCTAssertEqual(json["agent_subagent_event"] as? Bool, true)
        XCTAssertEqual(json["codex_collab_tool"] as? String, "spawnAgent")
        XCTAssertEqual(json["description"] as? String, "Review the diff")
        XCTAssertEqual(json["prompt"] as? String, "Review the diff")
        XCTAssertEqual(json["subagent_type"] as? String, "codex")
    }

    func testMapsTypedSubAgentStartDefaultsMissingInputFields() throws {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(
            .subAgent(AgentSubAgentEvent(
                id: "agent-1",
                phase: .started,
                description: "Inspect scripts"
            ))
        ))

        guard case .toolCall(_, let name, let input, _, _) = try XCTUnwrap(events.first) else {
            return XCTFail("Expected a tool call")
        }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(name, "Agent")
        let json = try Self.jsonObject(from: input)
        XCTAssertEqual(json["agent_subagent_event"] as? Bool, true)
        XCTAssertEqual(json["description"] as? String, "Inspect scripts")
        XCTAssertEqual(json["subagent_type"] as? String, "general-purpose")
    }

    func testCodexCollaborationTaskNoLongerMapsThroughCodexSpecificHelper() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.task(AgentTaskEvent(
            id: "spawn-1",
            phase: .started,
            description: "Review the diff",
            taskType: "collabAgentToolCall",
            lastToolName: "spawnAgent",
            metadata: ["codex_collab_tool": .string("spawnAgent")]
        )), providerId: .codex))

        XCTAssertTrue(events.isEmpty)
    }

    func testNonCodexTaskStillMapsThroughLegacySubAgentFallback() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.task(AgentTaskEvent(
            id: "agent-1",
            phase: .started,
            description: "Review the diff",
            taskType: "external_subagent"
        ))))

        XCTAssertEqual(events, [
            .subAgentStarted(
                toolUseId: "agent-1",
                description: "Review the diff",
                taskType: "external_subagent"
            )
        ])
    }

    func testIgnoresCodexWaitAndCloseCollaborationTasksForSubAgentLifecycle() {
        let waitEvents = AgentCLIKitEventMapper().conversationEvents(from: envelope(
            .task(AgentTaskEvent(
                id: "wait-1",
                phase: .started,
                description: "Wait for Dirac",
                taskType: "collabAgentToolCall",
                lastToolName: "waitAgent",
                metadata: ["codex_collab_tool": .string("waitAgent")]
            )),
            providerId: .codex
        ))
        let closeEvents = AgentCLIKitEventMapper().conversationEvents(from: envelope(
            .task(AgentTaskEvent(
                id: "close-1",
                phase: .completed,
                description: "Close Dirac",
                taskType: "collabAgentToolCall",
                lastToolName: "closeAgent",
                status: "completed",
                metadata: ["codex_collab_tool": .string("closeAgent")]
            )),
            providerId: .codex
        ))

        XCTAssertTrue(waitEvents.isEmpty)
        XCTAssertTrue(closeEvents.isEmpty)
    }

    func testMapsTypedSubAgentTerminalToHiddenSubAgentCompletionAndResult() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(
            .subAgent(AgentSubAgentEvent(
                id: "spawn-1",
                phase: .terminal,
                description: "Review the diff",
                status: "completed",
                result: "All done",
                toolUses: 2,
                totalTokens: 300,
                durationMs: 400
            )),
            providerId: .codex
        ))

        XCTAssertEqual(events, [
            .subAgentCompleted(
                toolUseId: "spawn-1",
                status: "completed",
                toolUses: 2,
                totalTokens: 300,
                durationMs: 400
            ),
            .toolResult(
                id: "spawn-1",
                output: "All done",
                isError: false,
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

    private static func jsonObject(from string: String) throws -> [String: Any] {
        let data = try XCTUnwrap(string.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
