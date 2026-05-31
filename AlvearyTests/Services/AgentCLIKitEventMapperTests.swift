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
