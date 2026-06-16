import XCTest

@testable import Alveary

@MainActor
extension ChatItemGrouperTests {
    func testPermissionApprovalStaysPinnedBelowLaterActivityRows() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let events = [
            pinnedApprovalBashCall(conversationId: conversationId, toolId: "tool-bash", command: "date"),
            pinnedApprovalBashApproval(conversationId: conversationId, toolId: "tool-bash", command: "date"),
            pinnedApprovalReadCall(conversationId: conversationId, toolId: "tool-read"),
            pinnedApprovalToolResult(conversationId: conversationId, toolId: "tool-read", output: "README.md")
        ]

        grouper.update(events: events)

        XCTAssertEqual(grouper.items.count, 3)
        guard case .standaloneTool(_, let bashTool) = grouper.items[0] else {
            return XCTFail("Expected the Bash row before the pinned approval")
        }
        XCTAssertEqual(bashTool.id, "tool-bash")
        guard case .toolGroup(_, let tools) = grouper.items[1] else {
            return XCTFail("Expected later activity to insert above the approval")
        }
        XCTAssertEqual(tools.map(\.id), ["tool-read"])
        XCTAssertTrue(tools.allSatisfy(\.isComplete))
        guard case .toolApproval(_, let request, let status) = grouper.items[2] else {
            return XCTFail("Expected the approval to remain pinned under the active run")
        }
        XCTAssertEqual(request.toolUseId, "tool-bash")
        XCTAssertNil(status)
    }

    func testResolvedPermissionApprovalReleasesBeforeNextAssistantMessage() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let events = [
            pinnedApprovalBashCall(conversationId: conversationId, toolId: "tool-bash", command: "date"),
            pinnedApprovalBashApproval(conversationId: conversationId, toolId: "tool-bash", command: "date", status: .approved),
            pinnedApprovalReadCall(conversationId: conversationId, toolId: "tool-read"),
            pinnedApprovalToolResult(conversationId: conversationId, toolId: "tool-read", output: "README.md"),
            pinnedApprovalAssistantMessage(conversationId: conversationId, content: "Done.")
        ]

        grouper.update(events: events)

        XCTAssertEqual(grouper.items.map(\.id), expectedResolvedPinnedApprovalItemIds)
        guard case .toolApproval(_, _, let status) = grouper.items[2] else {
            return XCTFail("Expected the resolved approval below the activity run")
        }
        XCTAssertEqual(status, .approved)
        guard case .assistantMessage(_, let text) = grouper.items[3] else {
            return XCTFail("Expected the assistant message below the released approval")
        }
        XCTAssertEqual(text, "Done.")
    }

    func testPermissionApprovalOrderingMatchesFullRebuildAfterResolution() {
        let conversationId = "conversation-1"
        let events = [
            pinnedApprovalBashCall(conversationId: conversationId, toolId: "tool-bash", command: "date"),
            pinnedApprovalBashApproval(conversationId: conversationId, toolId: "tool-bash", command: "date"),
            pinnedApprovalBashApproval(
                id: "approval-approved",
                conversationId: conversationId,
                toolId: "tool-bash",
                command: "date",
                status: .approved
            ),
            pinnedApprovalReadCall(conversationId: conversationId, toolId: "tool-read"),
            pinnedApprovalToolResult(conversationId: conversationId, toolId: "tool-read", output: "README.md"),
            pinnedApprovalAssistantMessage(conversationId: conversationId, content: "Done.")
        ]
        let incrementalGrouper = ChatItemGrouper()
        for event in events {
            incrementalGrouper.append(event: event)
        }
        let rebuiltGrouper = ChatItemGrouper()

        rebuiltGrouper.update(events: events, forceFullRebuild: true)

        XCTAssertEqual(rebuiltGrouper.items, incrementalGrouper.items)
        XCTAssertEqual(rebuiltGrouper.items.map(\.id), expectedResolvedPinnedApprovalItemIds)
    }

    func testUnresolvedPermissionApprovalStaysPinnedBelowLaterNonActivityRows() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let events = [
            pinnedApprovalBashCall(conversationId: conversationId, toolId: "tool-bash", command: "date"),
            pinnedApprovalBashApproval(conversationId: conversationId, toolId: "tool-bash", command: "date"),
            pinnedApprovalAssistantMessage(conversationId: conversationId, content: "Still waiting.")
        ]

        grouper.update(events: events)

        XCTAssertEqual(grouper.items.map(\.id), ["tool-tool-bash", "assistant-message", "approval-tool-bash"])
        guard case .toolApproval(_, _, let status) = grouper.items[2] else {
            return XCTFail("Expected the unresolved approval to stay pinned at the bottom")
        }
        XCTAssertNil(status)
    }

    func testResolvedPermissionApprovalReleasesAboveIncompleteTaskListBeforeAssistantMessage() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let events = [
            pinnedApprovalTodoWrite(conversationId: conversationId),
            pinnedApprovalBashCall(conversationId: conversationId, toolId: "tool-bash", command: "date"),
            pinnedApprovalBashApproval(conversationId: conversationId, toolId: "tool-bash", command: "date", status: .approved),
            pinnedApprovalReadCall(conversationId: conversationId, toolId: "tool-read"),
            pinnedApprovalToolResult(conversationId: conversationId, toolId: "tool-read", output: "README.md"),
            pinnedApprovalAssistantMessage(conversationId: conversationId, content: "Done.")
        ]

        grouper.update(events: events)

        XCTAssertEqual(
            grouper.items.map(\.id),
            [
                "tool-tool-bash",
                "group-read-call-tool-read",
                "approval-tool-bash",
                "assistant-message",
                "tasks-todo-1"
            ]
        )
        guard case .taskListBlock(_, let tasks) = grouper.items.last else {
            return XCTFail("Expected the incomplete task list to remain pinned below released approvals")
        }
        XCTAssertEqual(tasks.first?.status, .inProgress)
    }
}

private let expectedResolvedPinnedApprovalItemIds = [
    "tool-tool-bash",
    "group-read-call-tool-read",
    "approval-tool-bash",
    "assistant-message"
]

private func pinnedApprovalBashCall(
    conversationId: String,
    toolId: String,
    command: String
) -> ConversationEventRecord {
    ConversationEventRecord(
        id: "bash-call-\(toolId)",
        conversationId: conversationId,
        type: "tool_call",
        toolId: toolId,
        toolName: "Bash",
        toolInput: #"{"command":"\#(command)"}"#
    )
}

private func pinnedApprovalBashApproval(
    id: String = "approval",
    conversationId: String,
    toolId: String,
    command: String,
    status: ToolApprovalStatus? = nil
) -> ConversationEventRecord {
    ConversationEventRecord(
        id: id,
        conversationId: conversationId,
        type: "tool_approval",
        content: "session-123",
        toolId: toolId,
        toolName: "Bash",
        toolInput: #"{"command":"\#(command)"}"#,
        toolApprovalStatus: status?.rawValue
    )
}

private func pinnedApprovalReadCall(
    conversationId: String,
    toolId: String
) -> ConversationEventRecord {
    ConversationEventRecord(
        id: "read-call-\(toolId)",
        conversationId: conversationId,
        type: "tool_call",
        toolId: toolId,
        toolName: "Read",
        toolInput: #"{"file_path":"README.md"}"#
    )
}

private func pinnedApprovalToolResult(
    conversationId: String,
    toolId: String,
    output: String
) -> ConversationEventRecord {
    ConversationEventRecord(
        id: "result-\(toolId)",
        conversationId: conversationId,
        type: "tool_result",
        toolId: toolId,
        toolOutput: output
    )
}

private func pinnedApprovalAssistantMessage(
    conversationId: String,
    content: String
) -> ConversationEventRecord {
    ConversationEventRecord(
        id: "assistant-message",
        conversationId: conversationId,
        type: "message",
        role: "assistant",
        content: content
    )
}

private func pinnedApprovalTodoWrite(conversationId: String) -> ConversationEventRecord {
    ConversationEventRecord(
        id: "todo-write",
        conversationId: conversationId,
        type: "tool_call",
        toolId: "todo-1",
        toolName: "TodoWrite",
        toolInput: #"{ "todos": [{ "content": "Inspect transcript", "status": "in_progress" }] }"#
    )
}
