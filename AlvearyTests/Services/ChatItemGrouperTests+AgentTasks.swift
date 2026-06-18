import XCTest

@testable import Alveary

@MainActor
extension ChatItemGrouperTests {
    func testTaskListSnapshotRecordRendersTaskListBlock() throws {
        let grouper = ChatItemGrouper()
        let record = try taskListSnapshotRecord(
            id: "tasks-codex-plan-turn-1",
            items: [
                ConversationTaskListItem(id: "task-1", content: "Inspect", status: .completed),
                ConversationTaskListItem(
                    id: "task-2",
                    content: "Implement",
                    activeForm: "Implementing",
                    status: .inProgress
                ),
                ConversationTaskListItem(id: "task-3", content: "Verify", status: .pending)
            ]
        )

        grouper.update(events: [record])

        XCTAssertEqual(grouper.items.count, 1)
        let taskBlock = try XCTUnwrap(firstTaskListBlock(in: grouper.items))
        XCTAssertEqual(taskBlock.id, "tasks-codex-plan-turn-1")
        XCTAssertEqual(taskBlock.tasks, [
            TaskEntry(id: "task-1", content: "Inspect", activeForm: nil, status: .completed),
            TaskEntry(id: "task-2", content: "Implement", activeForm: "Implementing", status: .inProgress),
            TaskEntry(id: "task-3", content: "Verify", activeForm: nil, status: .pending)
        ])
    }

    func testTaskListSnapshotRecordReplacesSameId() throws {
        let grouper = ChatItemGrouper()
        let firstRecord = try taskListSnapshotRecord(
            id: "tasks-codex-plan-turn-1",
            items: [ConversationTaskListItem(id: "task-1", content: "Inspect", status: .inProgress)]
        )
        let secondRecord = try taskListSnapshotRecord(
            id: "tasks-codex-plan-turn-1",
            items: [ConversationTaskListItem(id: "task-1", content: "Inspect", status: .completed)]
        )

        grouper.update(events: [firstRecord, secondRecord])

        let taskBlocks = taskListBlocks(in: grouper.items)
        XCTAssertEqual(taskBlocks.count, 1)
        XCTAssertEqual(taskBlocks.first, [
            TaskEntry(id: "task-1", content: "Inspect", activeForm: nil, status: .completed)
        ])
    }

    func testClaudeTaskToolsRebuildAsSingleTaskListBlock() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"

        grouper.update(events: observedClaudeTaskEvents(conversationId: conversationId))

        XCTAssertFalse(renderedToolNames(in: grouper.items).contains("TaskCreate"))
        XCTAssertFalse(renderedToolNames(in: grouper.items).contains("TaskUpdate"))
        XCTAssertFalse(renderedToolNames(in: grouper.items).contains("ToolSearch"))

        let taskBlocks = taskListBlocks(in: grouper.items)
        XCTAssertEqual(taskBlocks.count, 1)
        XCTAssertEqual(taskBlocks.first?.map(\.content), [
            "Read index.html",
            "Inspect stylesheets",
            "List script files",
            "Check images directory"
        ])
        XCTAssertEqual(taskBlocks.first?.map(\.status), [.completed, .completed, .completed, .completed])
    }

    func testTodoWriteTaskListBehaviorRemainsUnchanged() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"

        grouper.update(events: [
            todoWriteRecord(
                id: "todo-write",
                toolId: "todo-list",
                conversationId: conversationId,
                content: "Keep TodoWrite behavior",
                status: .inProgress
            )
        ])

        XCTAssertEqual(grouper.items.count, 1)
        guard case .taskListBlock(let id, let tasks) = grouper.items[0] else {
            return XCTFail("Expected TodoWrite to still render a task-list block")
        }
        XCTAssertEqual(id, "tasks-todo-list")
        XCTAssertEqual(tasks, [
            TaskEntry(
                id: "task-0",
                content: "Keep TodoWrite behavior",
                activeForm: "Keeping TodoWrite behavior",
                status: .inProgress
            )
        ])
    }

    func testNonTaskToolSearchStillRendersNormally() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let toolSearch = ConversationEventRecord(
            id: "tool-search",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "tool-search-1",
            toolName: "ToolSearch",
            toolInput: #"{"query":"select:TaskCreate,Read","max_results":2}"#
        )

        grouper.update(events: [toolSearch])

        XCTAssertEqual(grouper.items.count, 1)
        guard case .toolGroup(_, let tools) = grouper.items[0] else {
            return XCTFail("Expected mixed ToolSearch to remain visible")
        }
        XCTAssertEqual(tools.map(\.name), ["ToolSearch"])
    }

    private func observedClaudeTaskEvents(conversationId: String) -> [ConversationEventRecord] {
        [
            assistantMessageRecord(
                id: "assistant-create",
                conversationId: conversationId,
                content: "Creating 4 tasks now."
            ),
            taskToolSearchRecord(id: "task-search", conversationId: conversationId),
            taskToolSearchResultRecord(id: "task-search-result", toolId: "task-search", conversationId: conversationId)
        ]
            + taskCreateRecords(conversationId: conversationId)
            + [
                assistantMessageRecord(
                    id: "assistant-progress",
                    conversationId: conversationId,
                    content: "4 tasks created. Simulating work now."
                )
            ]
            + taskUpdateRecords(conversationId: conversationId)
            + [
                assistantMessageRecord(
                    id: "assistant-final",
                    conversationId: conversationId,
                    content: "All 4 tasks cycled through pending -> in_progress -> completed. TODO list working."
                )
            ]
    }

    private func taskCreateRecords(conversationId: String) -> [ConversationEventRecord] {
        ["Read index.html", "Inspect stylesheets", "List script files", "Check images directory"]
            .enumerated()
            .flatMap { offset, subject in
                let taskId = "\(offset + 1)"
                let toolId = "task-create-\(taskId)"
                return [
                    taskCreateRecord(id: toolId, conversationId: conversationId, subject: subject),
                    taskCreateResultRecord(
                        id: "task-create-result-\(taskId)",
                        toolId: toolId,
                        conversationId: conversationId,
                        taskId: taskId,
                        subject: subject
                    )
                ]
            }
    }

    private func taskUpdateRecords(conversationId: String) -> [ConversationEventRecord] {
        ["1", "2", "3", "4"].flatMap { taskId in
            let inProgressToolId = "task-update-\(taskId)a"
            let completedToolId = "task-update-\(taskId)b"
            return [
                taskUpdateRecord(id: inProgressToolId, conversationId: conversationId, taskId: taskId, status: .inProgress),
                taskUpdateResultRecord(id: "task-update-result-\(taskId)a", toolId: inProgressToolId, conversationId: conversationId),
                taskUpdateRecord(id: completedToolId, conversationId: conversationId, taskId: taskId, status: .completed),
                taskUpdateResultRecord(id: "task-update-result-\(taskId)b", toolId: completedToolId, conversationId: conversationId)
            ]
        }
    }

    private func assistantMessageRecord(
        id: String,
        conversationId: String,
        content: String
    ) -> ConversationEventRecord {
        ConversationEventRecord(
            id: id,
            conversationId: conversationId,
            type: "message",
            role: "assistant",
            content: content
        )
    }

    private func taskToolSearchRecord(id: String, conversationId: String) -> ConversationEventRecord {
        ConversationEventRecord(
            id: id,
            conversationId: conversationId,
            type: "tool_call",
            toolId: id,
            toolName: "ToolSearch",
            toolInput: #"{"query":"select:TaskCreate,TaskUpdate,TaskList,TaskGet","max_results":4}"#
        )
    }

    private func taskToolSearchResultRecord(
        id: String,
        toolId: String,
        conversationId: String
    ) -> ConversationEventRecord {
        ConversationEventRecord(
            id: id,
            conversationId: conversationId,
            type: "tool_result",
            toolId: toolId,
            toolOutput: ""
        )
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

    private func taskUpdateRecord(
        id: String,
        conversationId: String,
        taskId: String,
        status: TaskEntry.Status
    ) -> ConversationEventRecord {
        ConversationEventRecord(
            id: id,
            conversationId: conversationId,
            type: "tool_call",
            toolId: id,
            toolName: "TaskUpdate",
            toolInput: #"{ "taskId": "\#(taskId)", "status": "\#(status.rawValue)" }"#
        )
    }

    private func taskUpdateResultRecord(
        id: String,
        toolId: String,
        conversationId: String
    ) -> ConversationEventRecord {
        ConversationEventRecord(
            id: id,
            conversationId: conversationId,
            type: "tool_result",
            toolId: toolId,
            toolOutput: "Task updated successfully."
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

    private func taskListBlocks(in items: [ChatItem]) -> [[TaskEntry]] {
        items.compactMap { item -> [TaskEntry]? in
            guard case .taskListBlock(_, let tasks) = item else {
                return nil
            }
            return tasks
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

    private func taskListSnapshotRecord(
        id: String,
        items: [ConversationTaskListItem]
    ) throws -> ConversationEventRecord {
        let conversation = Conversation(provider: "codex")
        return try XCTUnwrap(ConversationEvent.taskListSnapshot(
            ConversationTaskListSnapshot(id: id, items: items)
        ).toRecord(conversation: conversation))
    }
}
