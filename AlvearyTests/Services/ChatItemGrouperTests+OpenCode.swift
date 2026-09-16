import AgentCLIKit
import XCTest

@testable import Alveary

extension ChatItemGrouperTests {
    func testNativeToolAfterPermissionDoesNotInventAnotherApproval() throws {
        let mapper = AgentCLIKitEventMapper()
        let envelope = AgentEventEnvelope(
            generation: 1, index: 0, harnessId: .opencode, conversationId: "conversation", harnessSessionId: "ses_native",
            source: .runtime, event: .toolCall(AgentToolCallEvent(
                id: "opencode:ses_native:msg_1:call_bash", name: "bash", input: .object(["command": .string("pwd")])
            ))
        )
        let mapped = try XCTUnwrap(mapper.conversationEvents(from: envelope).first)
        guard case let .toolCall(id, name, input, _, _) = mapped else { return XCTFail("Expected native call") }
        let approval = ConversationEventRecord(
            conversationId: "conversation", type: "tool_approval", content: "ses_native", toolId: "per_native", toolName: "Bash",
            toolInput: #"{"command":"git status"}"#
        )
        let call = ConversationEventRecord(
            conversationId: "conversation", type: "tool_call", toolId: id, toolName: name, toolInput: input
        )
        let grouper = ChatItemGrouper()
        grouper.update(events: [approval, call])
        let approvalIDs = grouper.items.flatMap { item -> [String] in
            switch item {
            case let .toolApproval(_, request, _): return [request.toolUseId]
            case let .toolApprovalBatch(_, requests, _): return requests.map(\.toolUseId)
            default: return []
            }
        }
        XCTAssertEqual(approvalIDs, ["per_native"])
        XCTAssertTrue(grouper.items.contains {
            guard case let .standaloneTool(_, tool) = $0 else { return false }
            return tool.id == id
        })
    }
}
