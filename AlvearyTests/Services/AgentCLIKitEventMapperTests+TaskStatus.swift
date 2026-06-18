import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

extension AgentCLIKitEventMapperTests {
    func testMapsCodexSpawnAgentStartToMarkedAgentToolCall() throws {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(
            .task(AgentTaskEvent(
                id: "spawn-1",
                phase: .started,
                description: "Review the diff",
                taskType: "collabAgentToolCall",
                lastToolName: "spawnAgent",
                metadata: [
                    "codex_collab_tool": .string("spawnAgent"),
                    "prompt": .string("Review the diff")
                ]
            )),
            providerId: .codex
        ))

        XCTAssertEqual(events.count, 1)
        guard case .toolCall(let id, let name, let input, let parentToolUseId, let callerAgent) = try XCTUnwrap(events.first) else {
            return XCTFail("Expected a tool call")
        }
        XCTAssertEqual(id, "spawn-1")
        XCTAssertEqual(name, "Agent")
        XCTAssertNil(parentToolUseId)
        XCTAssertNil(callerAgent)

        let json = try Self.jsonObject(from: input)
        XCTAssertEqual(json["codex_collab_tool"] as? String, "spawnAgent")
        XCTAssertEqual(json["description"] as? String, "Review the diff")
        XCTAssertEqual(json["prompt"] as? String, "Review the diff")
        XCTAssertEqual(json["subagent_type"] as? String, "codex")
    }

    func testMapsCodexSpawnAgentSnakeCaseStartToMarkedAgentToolCall() throws {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(
            .task(AgentTaskEvent(
                id: "spawn-1",
                phase: .started,
                description: "Inspect scripts",
                taskType: "collabAgentToolCall",
                lastToolName: "spawn_agent",
                metadata: ["codex_collab_tool": .string("spawn_agent")]
            )),
            providerId: .codex
        ))

        guard case .toolCall(_, let name, let input, _, _) = try XCTUnwrap(events.first) else {
            return XCTFail("Expected a tool call")
        }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(name, "Agent")
        XCTAssertEqual(try Self.jsonObject(from: input)["codex_collab_tool"] as? String, "spawnAgent")
    }

    func testDoesNotMapNonCodexSpawnAgentTaskToCodexAgentToolCall() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.task(AgentTaskEvent(
            id: "spawn-1",
            phase: .started,
            description: "Review the diff",
            taskType: "collabAgentToolCall",
            lastToolName: "spawnAgent",
            metadata: ["codex_collab_tool": .string("spawnAgent")]
        ))))

        XCTAssertEqual(events, [
            .subAgentStarted(
                toolUseId: "spawn-1",
                description: "Review the diff",
                taskType: "collabAgentToolCall"
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

    func testMapsCodexSpawnAgentCompletionToHiddenSubAgentCompletionOnly() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(
            .task(AgentTaskEvent(
                id: "spawn-1",
                phase: .completed,
                description: "Review the diff",
                taskType: "collabAgentToolCall",
                lastToolName: "spawnAgent",
                toolUses: 2,
                totalTokens: 300,
                durationMs: 400,
                status: "completed",
                metadata: ["codex_collab_tool": .string("spawnAgent")]
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
