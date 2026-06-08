import AgentCLIKit
import XCTest

@testable import Alveary

final class AgentCLIKitEventMapperTests: XCTestCase {
    func testMapsToolCallMetadata() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.toolCall(AgentToolCallEvent(
            id: "tool-1",
            name: "Bash",
            input: .object(["command": .string("pwd")]),
            metadata: [
                "parent_tool_use_id": .string("parent-1"),
                "caller_agent": .string("sub-agent")
            ]
        ))))

        guard case let .toolCall(id, name, input, parentToolUseId, callerAgent)? = events.first else {
            return XCTFail("Expected tool call event")
        }
        XCTAssertEqual(id, "tool-1")
        XCTAssertEqual(name, "Bash")
        XCTAssertEqual(Self.object(from: input)?["command"] as? String, "pwd")
        XCTAssertEqual(parentToolUseId, "parent-1")
        XCTAssertEqual(callerAgent, "sub-agent")
    }

    func testMapsUsageAndPermissionDenials() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.usage(AgentUsageEvent(
            model: "sonnet",
            inputTokens: 1,
            outputTokens: 2,
            cacheReadInputTokens: 3,
            cacheCreationInputTokens: 4,
            durationMs: 50,
            costUSD: 0.01,
            contextWindow: 200_000,
            stopReason: "permission_denial",
            isTerminal: true,
            isError: true,
            permissionDenials: [
                AgentPermissionDenialSummary(toolUseId: "tool-1", toolName: "Bash", reason: "Denied")
            ]
        ))))

        XCTAssertEqual(events, [
            .tokens(
                input: 1,
                output: 2,
                cacheRead: 3,
                cacheCreation: 4,
                isError: true,
                stopReason: "permission_denial",
                durationMs: 50,
                costUsd: 0.01,
                providerModelId: "sonnet",
                contextWindowSize: 200_000,
                permissionDenials: [PermissionDenialSummary(toolName: "Bash", toolUseId: "tool-1")]
            )
        ])
    }

    func testMapsUsageStopReasonFromMetadataFallback() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.usage(AgentUsageEvent(
            model: nil,
            inputTokens: 0,
            outputTokens: 0,
            metadata: ["stop_reason": .string("tool_deferred")]
        ))))

        guard case let .tokens(_, _, _, _, _, stopReason, _, _, _, _, _)? = events.first else {
            return XCTFail("Expected token event")
        }
        XCTAssertEqual(stopReason, "tool_deferred")
    }

    func testMapsMissingUsageCostAsNil() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.usage(AgentUsageEvent(
            model: nil,
            inputTokens: 1,
            outputTokens: 2
        ))))

        guard case let .tokens(_, _, _, _, _, _, _, costUsd, _, _, _)? = events.first else {
            return XCTFail("Expected token event")
        }
        XCTAssertNil(costUsd)
    }

    func testMapsCompletedTaskNotificationToSubAgentCompletionAndResult() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.task(AgentTaskEvent(
            id: "agent-tool-1",
            phase: .notification,
            description: "Agent completed",
            toolUses: 2,
            totalTokens: 1234,
            durationMs: 5678,
            status: "completed",
            metadata: [
                "result": .string("Async result"),
                "summary": .string("Agent completed")
            ]
        ))))

        XCTAssertEqual(events, [
            .subAgentCompleted(
                toolUseId: "agent-tool-1",
                status: "completed",
                toolUses: 2,
                totalTokens: 1234,
                durationMs: 5678
            ),
            .toolResult(
                id: "agent-tool-1",
                output: "Async result",
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

    func testMapsCompletedTaskWithoutOutputOnlyToSubAgentCompletion() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.task(AgentTaskEvent(
            id: "agent-tool-1",
            phase: .completed,
            status: "completed"
        ))))

        XCTAssertEqual(events, [
            .subAgentCompleted(
                toolUseId: "agent-tool-1",
                status: "completed",
                toolUses: 0,
                totalTokens: 0,
                durationMs: 0
            )
        ])
    }

    func testMapsContextCompactionEvents() {
        let mapper = AgentCLIKitEventMapper()

        let started = mapper.conversationEvents(from: envelope(.contextCompaction(AgentContextCompactionEvent(
            id: "compact-1",
            phase: .started,
            trigger: "auto"
        ))))
        let completed = mapper.conversationEvents(from: envelope(.contextCompaction(AgentContextCompactionEvent(
            id: "compact-1",
            phase: .completed,
            summary: "Reduced context"
        ))))
        let failed = mapper.conversationEvents(from: envelope(.contextCompaction(AgentContextCompactionEvent(
            id: "compact-2",
            phase: .failed,
            summary: "Fallback summary",
            errorMessage: "Compact hook failed"
        ))))

        XCTAssertEqual(started, [.contextCompactionStarted(id: "compact-1", trigger: "auto")])
        XCTAssertEqual(completed, [.contextCompactionCompleted(id: "compact-1", summary: "Reduced context")])
        XCTAssertEqual(failed, [.contextCompactionFailed(id: "compact-2", error: "Compact hook failed")])
    }

    func testMapsRawClaudeTaskNotificationToSubAgentResultOutput() throws {
        let taskNotification = """
        <task-notification>
        <task-id>agent-task-1</task-id>
        <tool-use-id>agent-tool-1</tool-use-id>
        <output-file>/tmp/agent-task-1.output</output-file>
        <status>completed</status>
        <summary>Agent "Audit CSS" completed</summary>
        <result>## Result

        - Found `--primary-color-lighter`
        - Replace `&lt;span&gt;` with `&lt;a&gt;`
        </result>
        <usage><total_tokens>14816</total_tokens><tool_uses>3</tool_uses><duration_ms>9929</duration_ms></usage>
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
        let decodedEvents = try ClaudeStreamDecoder().decodeLine(line)
        let events = decodedEvents.flatMap {
            AgentCLIKitEventMapper().conversationEvents(from: envelope($0))
        }

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first, .subAgentCompleted(
            toolUseId: "agent-tool-1",
            status: "completed",
            toolUses: 3,
            totalTokens: 14816,
            durationMs: 9929
        ))
        guard case let .toolResult(id, output, isError, parentToolUseId, metadata)? = events.last else {
            return XCTFail("Expected task notification to map to tool result")
        }
        XCTAssertEqual(id, "agent-tool-1")
        XCTAssertTrue(output.contains("## Result"))
        XCTAssertTrue(output.contains("Found `--primary-color-lighter`"))
        XCTAssertTrue(output.contains("Replace `<span>` with `<a>`"))
        XCTAssertFalse(isError)
        XCTAssertNil(parentToolUseId)
        XCTAssertEqual(metadata?.noOutputExpected, false)
    }

    func testMapsQueuedClaudeTaskNotificationAttachmentToSubAgentResultOutput() throws {
        let taskNotification = """
        <task-notification>
        <task-id>agent-task-1</task-id>
        <tool-use-id>agent-tool-1</tool-use-id>
        <output-file>/tmp/agent-task-1.output</output-file>
        <status>completed</status>
        <summary>Agent "Count HTML" completed</summary>
        <result>| Metric | Count |
        |---|---|
        | `&lt;script&gt;` tags | 5 |</result>
        <usage><total_tokens>16429</total_tokens><tool_uses>1</tool_uses><duration_ms>3048</duration_ms></usage>
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
        let decodedEvents = try ClaudeStreamDecoder().decodeLine(line)
        let events = decodedEvents.flatMap {
            AgentCLIKitEventMapper().conversationEvents(from: envelope($0))
        }

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first, .subAgentCompleted(
            toolUseId: "agent-tool-1",
            status: "completed",
            toolUses: 1,
            totalTokens: 16429,
            durationMs: 3048
        ))
        guard case let .toolResult(id, output, isError, parentToolUseId, metadata)? = events.last else {
            return XCTFail("Expected queued task notification to map to tool result")
        }
        XCTAssertEqual(id, "agent-tool-1")
        XCTAssertTrue(output.contains("| Metric | Count |"))
        XCTAssertTrue(output.contains("`<script>` tags"))
        XCTAssertFalse(isError)
        XCTAssertNil(parentToolUseId)
        XCTAssertEqual(metadata?.noOutputExpected, false)
    }

    func testMapsQueueOperationTaskNotificationToSubAgentResultOutput() throws {
        let taskNotification = """
        <task-notification>
        <task-id>agent-task-1</task-id>
        <tool-use-id>agent-tool-1</tool-use-id>
        <output-file>/tmp/agent-task-1.output</output-file>
        <status>completed</status>
        <summary>Agent "Find CSS custom properties" completed</summary>
        <result>CSS custom properties:
        - `--primary-color`
        - `--primary-color-lighter` (dark only)</result>
        <usage><total_tokens>10843</total_tokens><tool_uses>2</tool_uses><duration_ms>3313</duration_ms></usage>
        </task-notification>
        """
        let lineData = try JSONSerialization.data(withJSONObject: [
            "type": "queue-operation",
            "operation": "enqueue",
            "sessionId": "session-123",
            "content": taskNotification
        ] as [String: Any])
        let line = try XCTUnwrap(String(data: lineData, encoding: .utf8))
        let decodedEvents = try ClaudeStreamDecoder().decodeLine(line)
        let events = decodedEvents.flatMap {
            AgentCLIKitEventMapper().conversationEvents(from: envelope($0))
        }

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first, .subAgentCompleted(
            toolUseId: "agent-tool-1",
            status: "completed",
            toolUses: 2,
            totalTokens: 10843,
            durationMs: 3313
        ))
        guard case let .toolResult(id, output, isError, parentToolUseId, metadata)? = events.last else {
            return XCTFail("Expected queue-operation task notification to map to tool result")
        }
        XCTAssertEqual(id, "agent-tool-1")
        XCTAssertTrue(output.contains("CSS custom properties:"))
        XCTAssertTrue(output.contains("`--primary-color-lighter` (dark only)"))
        XCTAssertFalse(isError)
        XCTAssertNil(parentToolUseId)
        XCTAssertEqual(metadata?.noOutputExpected, false)
    }

    func testMapsClaudeAssistantUsageAsInterimUsageUpdate() throws {
        let decodedEvents = try ClaudeStreamDecoder().decodeLine(#"""
        {
          "type": "assistant",
          "model": "sonnet",
          "message": {
            "role": "assistant",
            "content": [{"type": "text", "text": "Working"}],
            "usage": {
              "input_tokens": 12,
              "output_tokens": 3
            }
          }
        }
        """#)
        let conversationEvents = decodedEvents.flatMap {
            AgentCLIKitEventMapper().conversationEvents(from: envelope($0))
        }
        let tokenEvents = conversationEvents.compactMap { event -> String? in
            guard case let .tokens(_, _, _, _, _, stopReason, _, _, _, _, _) = event else {
                return nil
            }
            return stopReason
        }

        XCTAssertEqual(tokenEvents, [ConversationEvent.interimUsageStopReason])
    }

    func testMapsPromptInteractionToToolApprovalRequest() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(
            .interaction(AgentInteractionEvent(
                id: "prompt-1",
                kind: .prompt,
                prompt: "Pick one",
                metadata: [
                    "session_id": .string("session-1"),
                    "tool_input": .object(["question": .string("Pick one")])
                ]
            )),
            providerSessionId: "session-1"
        ))

        guard case let .toolApprovalRequested(request)? = events.first else {
            return XCTFail("Expected tool approval request")
        }
        XCTAssertEqual(request.sessionId, "session-1")
        XCTAssertEqual(request.toolUseId, "prompt-1")
        XCTAssertEqual(request.toolName, "AskUserQuestion")
        XCTAssertEqual(Self.object(from: request.toolInput)?["question"] as? String, "Pick one")
    }

    func testMapsSystemInitDiagnosticToSessionInit() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(
            .diagnostic(AgentDiagnosticEvent(
                severity: .info,
                message: "init",
                metadata: ["session_id": .string("session-1")]
            ))
        ))

        XCTAssertEqual(events, [.sessionInit(sessionId: "session-1")])
    }

    func testMapsSessionMetadataToProviderSessionMetadataChanged() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(
            .sessionMetadata(AgentSessionMetadataEvent(providerSessionId: "thread-1", name: "Generated thread name", preview: "Initial preview")),
            providerSessionId: "thread-1"
        ))

        XCTAssertEqual(events, [.providerSessionMetadataChanged(sessionId: "thread-1", name: "Generated thread name", preview: "Initial preview")])
    }

    func testMapsHookApprovalFailureDiagnostic() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(
            .diagnostic(AgentDiagnosticEvent(
                code: .hookApprovalFailed,
                severity: .error,
                message: "Claude hook failed",
                metadata: [
                    "session_id": .string("session-1"),
                    "tool_use_id": .string("tool-1"),
                    "tool_name": .string("Edit")
                ]
            ))
        ))

        XCTAssertEqual(events, [
            .toolApprovalFailed(ToolApprovalFailure(
                sessionId: "session-1",
                toolUseId: "tool-1",
                toolName: "Edit",
                message: "Claude hook failed"
            ))
        ])
    }

    private func envelope(
        _ event: AgentCLIKit.AgentEvent,
        providerSessionId: AgentSessionID? = nil
    ) -> AgentCLIKit.AgentEventEnvelope {
        AgentCLIKit.AgentEventEnvelope(
            generation: 1,
            index: 0,
            providerId: .claude,
            conversationId: "conversation",
            providerSessionId: providerSessionId,
            source: .stdout,
            event: event,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func object(from json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
