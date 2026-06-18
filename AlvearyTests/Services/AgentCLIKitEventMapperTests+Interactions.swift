import AgentCLIKit
import XCTest

@testable import Alveary

extension AgentCLIKitEventMapperTests {
    func testMapsPromptInteractionToToolApprovalAndToolCall() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(
            .interaction(AgentInteractionEvent(
                id: "prompt-1",
                kind: .prompt,
                prompt: "Pick one",
                metadata: [
                    "session_id": .string("session-1"),
                    "tool_input": .object([
                        "questions": .array([
                            .object([
                                "question": .string("Pick one"),
                                "options": .array([.object(["label": .string("A")])])
                            ])
                        ])
                    ])
                ]
            )),
            providerSessionId: "session-1"
        ))

        guard case let .toolApprovalRequested(request)? = events.first,
              case let .toolCall(id, name, input, parentToolUseId, callerAgent)? = events.dropFirst().first else {
            return XCTFail("Expected approval and tool call events")
        }
        XCTAssertEqual(request.sessionId, "session-1")
        XCTAssertEqual(request.toolUseId, "prompt-1")
        XCTAssertEqual(request.toolName, "AskUserQuestion")
        XCTAssertEqual(firstQuestionText(from: request.toolInput), "Pick one")
        XCTAssertEqual(id, "prompt-1")
        XCTAssertEqual(name, "AskUserQuestion")
        XCTAssertEqual(firstQuestionText(from: input), "Pick one")
        XCTAssertNil(parentToolUseId)
        XCTAssertNil(callerAgent)
    }

    func testMapsPlanModeExitInteractionOnlyToToolApprovalRequest() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(
            .interaction(AgentInteractionEvent(
                id: "plan-1",
                kind: .planModeExit,
                prompt: "Implement this plan?",
                metadata: [
                    "session_id": .string("session-1"),
                    "tool_name": .string("ExitPlanMode"),
                    "tool_input": .object([:])
                ]
            )),
            providerSessionId: "session-1"
        ))

        XCTAssertEqual(events.count, 1)
        guard case let .toolApprovalRequested(request)? = events.first else {
            return XCTFail("Expected tool approval request")
        }
        XCTAssertEqual(request.toolUseId, "plan-1")
        XCTAssertEqual(request.toolName, "ExitPlanMode")
        XCTAssertEqual(request.toolInput, "{}")
    }

    func testMapsApprovalIdentityMetadataToToolApprovalRequest() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(
            .interaction(AgentInteractionEvent(
                id: "approval-1",
                kind: .approval,
                prompt: "Approve Bash command?",
                metadata: [
                    "session_id": .string("session-1"),
                    "tool_name": .string("Bash"),
                    "tool_input": .object(["command": .string(#"/bin/zsh -lc 'git add README.md'"#)]),
                    "approval_identity_tool_input": .object(["command": .string("git add README.md")])
                ]
            )),
            providerSessionId: "session-1"
        ))

        guard case let .toolApprovalRequested(request)? = events.first else {
            return XCTFail("Expected tool approval request")
        }
        XCTAssertEqual(request.toolInput, #"{"command":"\/bin\/zsh -lc 'git add README.md'"}"#)
        XCTAssertEqual(request.approvalIdentityToolInput, #"{"command":"git add README.md"}"#)
        XCTAssertEqual(request.conciseSummary, "git add README.md")
    }

    func testMapsMarkedRuntimePlanImplementationMessageToRuntimeUserMessage() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(
            .message(AgentMessageEvent(
                role: .user,
                text: "Implement plan",
                metadata: ["agent_plan_exit_interaction_id": .string("plan-1")]
            ))
        ))

        XCTAssertEqual(events, [.runtimeUserMessage(content: "Implement plan")])
    }

    func testMapsUnmarkedUserMessageAsDroppableMessageEcho() {
        let events = AgentCLIKitEventMapper().conversationEvents(from: envelope(
            .message(AgentMessageEvent(role: .user, text: "Implement plan"))
        ))

        XCTAssertEqual(events, [.message(role: "user", content: "Implement plan", parentToolUseId: nil)])
    }

    private func firstQuestionText(from json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (object["questions"] as? [[String: Any]])?.first?["question"] as? String
    }
}
