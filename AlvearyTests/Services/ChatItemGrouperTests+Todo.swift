import XCTest

@testable import Alveary

@MainActor
extension ChatItemGrouperTests {
    func testIncompleteTodoListStaysPinnedBelowNewMessages() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let todoWrite = todoWriteRecord(
            id: "todo-write",
            conversationId: conversationId,
            content: "Inspect transcript",
            status: .inProgress,
            activeForm: "Inspecting transcript"
        )
        let assistantMessage = assistantMessageRecord(
            id: "assistant-message",
            conversationId: conversationId,
            content: "I found the transcript code."
        )
        let userMessage = messageRecord(
            id: "user-message",
            conversationId: conversationId,
            role: "user",
            content: "Also check the checklist."
        )

        grouper.update(events: [todoWrite, assistantMessage, userMessage])

        XCTAssertEqual(grouper.items.count, 3)
        guard case .assistantMessage = grouper.items[0] else {
            return XCTFail("Expected assistant message above the pinned todo list")
        }
        guard case .userMessage = grouper.items[1] else {
            return XCTFail("Expected user message above the pinned todo list")
        }
        guard case .taskListBlock(_, let tasks) = grouper.items[2] else {
            return XCTFail("Expected incomplete todo list to stay at the bottom")
        }
        XCTAssertEqual(tasks.first?.status, .inProgress)
    }

    func testCompletedTodoListStopsPinningNewMessages() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let initialTodoWrite = todoWriteRecord(
            id: "todo-write-1",
            toolId: "todo-list-1",
            conversationId: conversationId,
            content: "Inspect transcript",
            status: .inProgress,
            activeForm: "Inspecting transcript"
        )
        let progressMessage = assistantMessageRecord(
            id: "progress-message",
            conversationId: conversationId,
            content: "I found the transcript code."
        )
        let completedTodoWrite = todoWriteRecord(
            id: "todo-write-2",
            toolId: "todo-list-1",
            conversationId: conversationId,
            content: "Inspect transcript",
            status: .completed
        )
        let finalMessage = assistantMessageRecord(
            id: "final-message",
            conversationId: conversationId,
            content: "Done."
        )

        grouper.update(events: [initialTodoWrite, progressMessage, completedTodoWrite, finalMessage])

        XCTAssertEqual(grouper.items.count, 3)
        guard case .assistantMessage = grouper.items[0] else {
            return XCTFail("Expected earlier assistant message first")
        }
        guard case .taskListBlock(_, let tasks) = grouper.items[1] else {
            return XCTFail("Expected completed todo list to remain in transcript order")
        }
        XCTAssertTrue(tasks.allSatisfy { $0.status == .completed })
        guard case .assistantMessage(_, let text) = grouper.items[2] else {
            return XCTFail("Expected final assistant message below completed todo list")
        }
        XCTAssertEqual(text, "Done.")
    }

    func testNewTodoListKeepsPreviousTodoListBehind() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let firstTodoWrite = todoWriteRecord(
            id: "todo-write-1",
            conversationId: conversationId,
            content: "Inspect transcript",
            status: .inProgress,
            activeForm: "Inspecting transcript"
        )
        let progressMessage = assistantMessageRecord(
            id: "progress-message",
            conversationId: conversationId,
            content: "I found the transcript code."
        )
        let secondTodoWrite = todoWriteRecord(
            id: "todo-write-2",
            conversationId: conversationId,
            content: "Update checklist",
            status: .inProgress,
            activeForm: "Updating checklist"
        )
        let nextMessage = assistantMessageRecord(
            id: "next-message",
            conversationId: conversationId,
            content: "The next todo list is active."
        )

        grouper.update(events: [firstTodoWrite, progressMessage, secondTodoWrite, nextMessage])

        XCTAssertEqual(grouper.items.count, 4)
        guard case .assistantMessage = grouper.items[0] else {
            return XCTFail("Expected progress message above the first pinned todo list")
        }
        guard case .taskListBlock(_, let previousTasks) = grouper.items[1] else {
            return XCTFail("Expected previous todo list to remain behind")
        }
        XCTAssertEqual(previousTasks.first?.content, "Inspect transcript")
        guard case .assistantMessage = grouper.items[2] else {
            return XCTFail("Expected new message above the latest pinned todo list")
        }
        guard case .taskListBlock(_, let latestTasks) = grouper.items[3] else {
            return XCTFail("Expected latest incomplete todo list to pin to the bottom")
        }
        XCTAssertEqual(latestTasks.first?.content, "Update checklist")
    }

    func testTodoListWithSameToolIdReplacesExistingBlock() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let initialTodoWrite = todoWriteRecord(
            id: "todo-write-event-1",
            toolId: "todo-list-1",
            conversationId: conversationId,
            content: "Inspect transcript",
            status: .inProgress,
            activeForm: "Inspecting transcript"
        )
        let updatedTodoWrite = todoWriteRecord(
            id: "todo-write-event-2",
            toolId: "todo-list-1",
            conversationId: conversationId,
            content: "Inspect transcript",
            status: .completed
        )

        grouper.update(events: [initialTodoWrite, updatedTodoWrite])

        XCTAssertEqual(grouper.items.count, 1)
        guard case .taskListBlock(let id, let tasks) = grouper.items[0] else {
            return XCTFail("Expected updated todo list")
        }
        XCTAssertEqual(id, "tasks-todo-list-1")
        XCTAssertEqual(tasks.first?.status, .completed)
    }

    func testTodoListWithDifferentToolIdButSameTasksReplacesExistingBlock() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let firstTodoWrite = todoWriteRecord(
            id: "todo-write-event-1",
            toolId: "todo-list-1",
            conversationId: conversationId,
            todos: [
                TodoFixture("List files in scripts/", .inProgress, "Listing files in scripts/"),
                TodoFixture("Count lines in index.html", .pending),
                TodoFixture("List stylesheets in styles/", .pending)
            ]
        )
        let secondTodoWrite = todoWriteRecord(
            id: "todo-write-event-2",
            toolId: "todo-list-2",
            conversationId: conversationId,
            todos: [
                TodoFixture("List files in scripts/", .completed),
                TodoFixture("Count lines in index.html", .inProgress, "Counting lines in index.html"),
                TodoFixture("List stylesheets in styles/", .pending)
            ]
        )

        grouper.update(events: [firstTodoWrite, secondTodoWrite])

        XCTAssertEqual(grouper.items.count, 1)
        guard case .taskListBlock(let id, let tasks) = grouper.items[0] else {
            return XCTFail("Expected the second TodoWrite to update the existing task list")
        }
        XCTAssertEqual(id, "tasks-todo-list-1")
        XCTAssertEqual(tasks.map(\.status), [.completed, .inProgress, .pending])
    }

    func testTodoListContentFallbackOnlyMatchesLatestTaskList() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let firstTodoWrite = todoWriteRecord(
            id: "todo-write-event-1",
            toolId: "todo-list-1",
            conversationId: conversationId,
            content: "Inspect transcript",
            status: .inProgress,
            activeForm: "Inspecting transcript"
        )
        let secondTodoWrite = todoWriteRecord(
            id: "todo-write-event-2",
            toolId: "todo-list-2",
            conversationId: conversationId,
            content: "Update checklist",
            status: .inProgress,
            activeForm: "Updating checklist"
        )
        let thirdTodoWrite = todoWriteRecord(
            id: "todo-write-event-3",
            toolId: "todo-list-3",
            conversationId: conversationId,
            content: "Inspect transcript",
            status: .completed
        )

        grouper.update(events: [firstTodoWrite, secondTodoWrite, thirdTodoWrite])

        XCTAssertEqual(grouper.items.count, 3)
        guard case .taskListBlock(_, let latestTasks) = grouper.items[2] else {
            return XCTFail("Expected older matching content to append instead of replacing history")
        }
        XCTAssertEqual(latestTasks.first?.content, "Inspect transcript")
        XCTAssertEqual(latestTasks.first?.status, .completed)
    }

    func testTodoListContentFallbackDoesNotReplaceCompletedLatestTaskList() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let completedTodoWrite = todoWriteRecord(
            id: "todo-write-event-1",
            toolId: "todo-list-1",
            conversationId: conversationId,
            content: "Inspect transcript",
            status: .completed
        )
        let repeatedTodoWrite = todoWriteRecord(
            id: "todo-write-event-2",
            toolId: "todo-list-2",
            conversationId: conversationId,
            content: "Inspect transcript",
            status: .inProgress,
            activeForm: "Inspecting transcript"
        )

        grouper.update(events: [completedTodoWrite, repeatedTodoWrite])

        XCTAssertEqual(grouper.items.count, 2)
        guard case .taskListBlock(_, let completedTasks) = grouper.items[0] else {
            return XCTFail("Expected the completed todo list to remain in history")
        }
        XCTAssertTrue(completedTasks.allSatisfy { $0.status == .completed })
        guard case .taskListBlock(_, let repeatedTasks) = grouper.items[1] else {
            return XCTFail("Expected same-content new todo list to append after completion")
        }
        XCTAssertEqual(repeatedTasks.first?.status, .inProgress)
    }

    private func assistantMessageRecord(
        id: String,
        conversationId: String,
        content: String
    ) -> ConversationEventRecord {
        messageRecord(id: id, conversationId: conversationId, role: "assistant", content: content)
    }

    private func messageRecord(
        id: String,
        conversationId: String,
        role: String,
        content: String
    ) -> ConversationEventRecord {
        ConversationEventRecord(
            id: id,
            conversationId: conversationId,
            type: "message",
            role: role,
            content: content
        )
    }

    private func todoWriteRecord(
        id: String,
        toolId: String? = nil,
        conversationId: String,
        content: String,
        status: TaskEntry.Status,
        activeForm: String? = nil
    ) -> ConversationEventRecord {
        let activeFormJSON = activeForm.map { #","activeForm":"\#($0)""# } ?? ""
        return ConversationEventRecord(
            id: id,
            conversationId: conversationId,
            type: "tool_call",
            toolId: toolId ?? id.replacingOccurrences(of: "write-", with: ""),
            toolName: "TodoWrite",
            toolInput: #"{ "todos": [{ "content": "\#(content)", "status": "\#(status.rawValue)"\#(activeFormJSON) }] }"#
        )
    }

    private func todoWriteRecord(
        id: String,
        toolId: String,
        conversationId: String,
        todos: [TodoFixture]
    ) -> ConversationEventRecord {
        let todosJSON = todos.map { todo in
            let activeFormJSON = todo.activeForm.map { #","activeForm":"\#($0)""# } ?? ""
            return #"{ "content": "\#(todo.content)", "status": "\#(todo.status.rawValue)"\#(activeFormJSON) }"#
        }.joined(separator: ",")
        return ConversationEventRecord(
            id: id,
            conversationId: conversationId,
            type: "tool_call",
            toolId: toolId,
            toolName: "TodoWrite",
            toolInput: #"{ "todos": [\#(todosJSON)] }"#
        )
    }
}

private struct TodoFixture {
    let content: String
    let status: TaskEntry.Status
    let activeForm: String?

    init(_ content: String, _ status: TaskEntry.Status, _ activeForm: String? = nil) {
        self.content = content
        self.status = status
        self.activeForm = activeForm
    }
}
