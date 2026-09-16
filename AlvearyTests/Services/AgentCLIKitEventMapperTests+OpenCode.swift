import AgentCLIKit
import XCTest

@testable import Alveary

extension AgentCLIKitEventMapperTests {
    func testOpenCodeTaskHasOneCallAndResultWithTypedCompletion() throws {
        let mapper = AgentCLIKitEventMapper()
        let id = "opencode:ses_root:msg_1:call_1"
        let wire: [AgentEvent] = [
            .toolCall(AgentToolCallEvent(id: id, name: "task", input: .object(["subagent_type": .string("general")]))),
            .subAgent(AgentSubAgentEvent(id: id, phase: .started, agentType: "general", childSessionIds: ["ses_child"])),
            .message(AgentMessageEvent(role: .assistant, text: "Child reply", metadata: ["parent_tool_use_id": .string(id)])),
            .subAgent(AgentSubAgentEvent(id: id, phase: .terminal, status: "completed", result: "Child reply")),
            .toolResult(AgentToolResultEvent(id: id, isError: false, content: "Child reply", metadata: ["tool_name": .string("task")]))
        ]
        let events = wire.flatMap { mapper.conversationEvents(from: envelope($0, harnessId: .opencode)) }
        XCTAssertEqual(events.count, 4)
        guard case let .toolCall(toolID, name, input, _, _) = events[0] else { return XCTFail("Missing Agent call") }
        XCTAssertEqual(toolID, id)
        XCTAssertEqual(name, "Agent")
        XCTAssertTrue(input.contains("agent_subagent_event"))
        XCTAssertEqual(events[1], .message(role: "assistant", content: "Child reply", parentToolUseId: id))
        guard case let .subAgentCompleted(completedID, _, _, _, _) = events[2] else { return XCTFail("Missing completion") }
        XCTAssertEqual(completedID, id)
        guard case let .toolResult(resultID, _, _, _, _) = events[3] else { return XCTFail("Missing native result") }
        XCTAssertEqual(resultID, id)
    }

    func testOpenCodeNativeQuestionsUseInteractionIDAndPreserveClosedChoices() throws {
        let mapper = AgentCLIKitEventMapper()
        XCTAssertTrue(mapper.conversationEvents(from: envelope(.toolCall(AgentToolCallEvent(
            id: "native-tool", name: "question", input: .object([:])
        )), harnessId: .opencode)).isEmpty)
        let input: JSONValue = .object(["questions": .array([.object([
            "question": .string("Choose"), "id": .string("0"), "custom": .bool(false), "multiSelect": .bool(false),
            "options": .array([.object(["label": .string("A")])])
        ])])])
        let events = mapper.conversationEvents(from: envelope(.interaction(AgentInteractionEvent(
            id: "que_native", kind: .prompt, prompt: "Choose", metadata: [
                "session_id": .string("ses_native"), "tool_name": .string("AskUserQuestion"),
                "tool_use_id": .string("native-tool"), "tool_input": input
            ]
        )), harnessId: .opencode))
        guard case let .toolApprovalRequested(request) = events[0],
              case let .toolCall(id, name, serialized, _, _) = events[1] else { return XCTFail("Missing native question") }
        XCTAssertEqual(request.toolUseId, "que_native")
        XCTAssertEqual(id, "que_native")
        XCTAssertEqual(name, "AskUserQuestion")
        XCTAssertTrue(serialized.contains("\"custom\":false"))
        XCTAssertEqual(request.sessionId, "ses_native")
    }

    func testOpenCodeChildUsageCannotReplaceRootContextOrTriggerHandoff() {
        let childUsage = AgentUsageEvent(
            model: "provider/child", inputTokens: 190_000, outputTokens: 10, contextWindow: 200_000,
            stopReason: AgentUsageEvent.interimUsageStopReason, metadata: ["parent_tool_use_id": .string("task")]
        )
        XCTAssertTrue(AgentCLIKitEventMapper().conversationEvents(from: envelope(.usage(childUsage), harnessId: .opencode)).isEmpty)
    }

    func testOpenCodeCacheTokensRemainAdditiveAndInterimUsageDoesNotEndTurn() throws {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(.usage(AgentUsageEvent(
            model: "provider/model", inputTokens: 20, outputTokens: 5, cacheReadInputTokens: 150, cacheCreationInputTokens: 10,
            contextWindow: 200, stopReason: AgentUsageEvent.interimUsageStopReason
        )), harnessId: .opencode))
        let event = try XCTUnwrap(events.first)
        let payload = try XCTUnwrap(TokenEventPayload(event))
        XCTAssertEqual(ContextTokenAccounting(harnessID: "opencode").contextUsedTokens(
            input: payload.input, cacheRead: payload.cacheRead, cacheCreation: payload.cacheCreation
        ), 180)
        XCTAssertFalse(payload.completesTurn)
    }

    func testOpenCodeReadAndBashReuseExistingToolPresentations() throws {
        let mapper = AgentCLIKitEventMapper()
        let calls: [(String, JSONValue)] = [
            ("read", .object(["filePath": .string("/tmp/file.swift")])),
            ("bash", .object(["command": .string("git status")]))
        ]
        let events = calls.flatMap { name, input in
            mapper.conversationEvents(from: envelope(.toolCall(AgentToolCallEvent(id: name, name: name, input: input)), harnessId: .opencode))
        }
        guard case let .toolCall(_, read, input, _, _) = events[0],
              case let .toolCall(_, bash, _, _, _) = events[1] else { return XCTFail("Missing native calls") }
        XCTAssertEqual(read, "Read")
        XCTAssertTrue(input.contains("file_path"))
        XCTAssertEqual(bash, "Bash")
    }
}
