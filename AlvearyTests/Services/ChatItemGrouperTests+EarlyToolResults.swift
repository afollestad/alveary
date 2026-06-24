import XCTest

@testable import Alveary

@MainActor
extension ChatItemGrouperTests {
    func testGroupableToolResultBeforeCallCompletesLaterToolGroupRow() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let result = ConversationEventRecord(
            id: "read-result",
            conversationId: conversationId,
            type: "tool_result",
            toolId: "read-1",
            toolOutput: "README contents"
        )
        let call = ConversationEventRecord(
            id: "read-call",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "read-1",
            toolName: "Read",
            toolInput: #"{"file_path":"README.md"}"#
        )

        grouper.update(events: [result, call])

        XCTAssertEqual(grouper.items.count, 1)
        guard case .toolGroup(_, let tools) = grouper.items[0] else {
            return XCTFail("Expected the later read call to consume the cached result")
        }
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0].name, "Read")
        XCTAssertTrue(tools[0].isComplete)
        XCTAssertEqual(tools[0].output, "README contents")
        XCTAssertTrue(grouper.pendingToolResultEventsByToolId.isEmpty)
    }

    func testAgentTaskResultBeforeCallUpdatesTaskListBlock() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let result = taskCreateResultRecord(
            id: "task-create-result",
            toolId: "task-create-1",
            conversationId: conversationId,
            taskId: "1",
            subject: "Inspect repo"
        )
        let call = taskCreateRecord(id: "task-create-1", conversationId: conversationId, subject: "Inspect repo")

        grouper.update(events: [result, call])

        XCTAssertFalse(renderedToolNames(in: grouper.items).contains("TaskCreate"))
        let taskBlock = firstTaskListBlock(in: grouper.items)
        XCTAssertEqual(taskBlock?.tasks.map(\.content), ["Inspect repo"])
        XCTAssertEqual(taskBlock?.tasks.map(\.status), [.pending])
        XCTAssertTrue(grouper.pendingToolResultEventsByToolId.isEmpty)
    }

    func testTodoWriteResultBeforeCallIsDiscarded() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let result = ConversationEventRecord(
            id: "todo-result",
            conversationId: conversationId,
            type: "tool_result",
            toolId: "todo-list",
            toolOutput: ""
        )
        let call = todoWriteRecord(
            id: "todo-write",
            toolId: "todo-list",
            conversationId: conversationId,
            content: "Keep TodoWrite behavior",
            status: .inProgress
        )

        grouper.update(events: [result, call])

        XCTAssertEqual(grouper.items.count, 1)
        guard case .taskListBlock(let id, let tasks) = grouper.items[0] else {
            return XCTFail("Expected TodoWrite to render only a task-list block")
        }
        XCTAssertEqual(id, "tasks-todo-list")
        XCTAssertEqual(tasks.map(\.content), ["Keep TodoWrite behavior"])
        XCTAssertTrue(grouper.pendingToolResultEventsByToolId.isEmpty)
        XCTAssertTrue(renderedToolNames(in: grouper.items).isEmpty)
    }

    private func taskCreateRecord(
        id: String,
        conversationId: String,
        subject: String
    ) -> ConversationEventRecord {
        ConversationEventRecord(
            id: id,
            conversationId: conversationId,
            type: "tool_call",
            toolId: id,
            toolName: "TaskCreate",
            toolInput: #"{ "subject": "\#(subject)", "activeForm": "Working on \#(subject)" }"#
        )
    }

    private func taskCreateResultRecord(
        id: String,
        toolId: String,
        conversationId: String,
        taskId: String,
        subject: String
    ) -> ConversationEventRecord {
        ConversationEventRecord(
            id: id,
            conversationId: conversationId,
            type: "tool_result",
            toolId: toolId,
            toolOutput: "Task #\(taskId) created successfully: \(subject)"
        )
    }

    private func todoWriteRecord(
        id: String,
        toolId: String,
        conversationId: String,
        content: String,
        status: TaskEntry.Status
    ) -> ConversationEventRecord {
        ConversationEventRecord(
            id: id,
            conversationId: conversationId,
            type: "tool_call",
            toolId: toolId,
            toolName: "TodoWrite",
            toolInput: #"{ "todos": [{ "content": "\#(content)", "status": "\#(status.rawValue)", "activeForm": "Keeping TodoWrite behavior" }] }"#
        )
    }

    private func renderedToolNames(in items: [ChatItem]) -> [String] {
        items.flatMap { item -> [String] in
            switch item {
            case .toolGroup(_, let tools):
                return tools.map(\.name)
            case .standaloneTool(_, let tool):
                return [tool.name]
            default:
                return []
            }
        }
    }

    private func firstTaskListBlock(in items: [ChatItem]) -> (id: String, tasks: [TaskEntry])? {
        for item in items {
            guard case .taskListBlock(let id, let tasks) = item else {
                continue
            }
            return (id, tasks)
        }
        return nil
    }
}
