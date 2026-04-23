import XCTest

@testable import Alveary

@MainActor
final class ChatItemGrouperTests: XCTestCase {
    func testAppendThenFullRebuildKeepsTranscriptStable() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let userMessage = ConversationEventRecord(
            id: "user-message",
            conversationId: conversationId,
            type: "message",
            role: "user",
            content: "Hello"
        )
        let assistantMessage = ConversationEventRecord(
            id: "assistant-message",
            conversationId: conversationId,
            type: "message",
            role: "assistant",
            content: "Hi"
        )

        grouper.append(event: userMessage)
        grouper.append(event: assistantMessage)
        grouper.update(events: [userMessage, assistantMessage], forceFullRebuild: true)

        XCTAssertEqual(
            grouper.items,
            [
                .userMessage(id: "user-message", text: "Hello"),
                .assistantMessage(id: "assistant-message", text: "Hi")
            ]
        )
    }

    func testLateToolResultPatchesStandaloneBashTool() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let toolCall = ConversationEventRecord(
            id: "tool-call",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"git status\"}"
        )
        let toolResult = ConversationEventRecord(
            id: "tool-result",
            conversationId: conversationId,
            type: "tool_result",
            toolId: "tool-1",
            toolOutput: "clean"
        )

        grouper.update(events: [toolCall])
        grouper.update(events: [toolCall, toolResult])

        XCTAssertEqual(grouper.items.count, 1)
        guard case .standaloneTool(_, let tool) = grouper.items[0] else {
            return XCTFail("Expected a standalone Bash tool")
        }
        XCTAssertEqual(tool.output, "clean")
    }

    func testReadGrepCollapseIntoSingleToolGroup() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let read = ConversationEventRecord(
            id: "read",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "r1",
            toolName: "Read",
            toolInput: "{\"file_path\":\"a.swift\"}"
        )
        let grep = ConversationEventRecord(
            id: "grep",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "g1",
            toolName: "Grep",
            toolInput: "{\"pattern\":\"foo\"}"
        )

        grouper.update(events: [read, grep])

        XCTAssertEqual(grouper.items.count, 1)
        guard case .toolGroup(_, let tools) = grouper.items[0] else {
            return XCTFail("Expected a single tool group")
        }
        XCTAssertEqual(tools.count, 2)
        XCTAssertEqual(tools.map(\.name), ["Read", "Grep"])
    }

    func testThinkingEventsAreDropped() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let thinking = ConversationEventRecord(
            id: "thinking",
            conversationId: conversationId,
            type: "thinking",
            content: "Planning..."
        )

        grouper.update(events: [thinking])

        XCTAssertTrue(grouper.items.isEmpty, "Thinking events should not be rendered")
    }

    func testInterruptedStopEventRendersTurnInterruptedNote() {
        let grouper = ChatItemGrouper()
        let stop = ConversationEventRecord(
            id: "stop-1",
            conversationId: "conversation-1",
            type: "stop",
            content: ConversationInterruption.displayMessage
        )

        grouper.update(events: [stop])

        XCTAssertEqual(grouper.items, [.turnInterruptedNote(id: "stop-1")])
    }

    func testInterruptedNoteLookupOnlyConsidersCurrentTurn() {
        let items: [ChatItem] = [
            .userMessage(id: "user-1", text: "First turn"),
            .turnInterruptedNote(id: "stop-1"),
            .userMessage(id: "user-2", text: "Second turn")
        ]

        XCTAssertFalse(items.hasInterruptedNoteAfterLatestUserMessage)
        XCTAssertTrue((items + [.turnInterruptedNote(id: "stop-2")]).hasInterruptedNoteAfterLatestUserMessage)
    }

    func testStandaloneAfterGroupClosesAndStartsNewGroup() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let read = ConversationEventRecord(
            id: "read",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "r1",
            toolName: "Read",
            toolInput: "{\"file_path\":\"a.swift\"}"
        )
        let write = ConversationEventRecord(
            id: "write",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "w1",
            toolName: "Write",
            toolInput: "{\"file_path\":\"b.swift\",\"content\":\"x\"}"
        )
        let grep = ConversationEventRecord(
            id: "grep",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "g1",
            toolName: "Grep",
            toolInput: "{\"pattern\":\"foo\"}"
        )

        grouper.update(events: [read, write, grep])

        XCTAssertEqual(grouper.items.count, 3)
        if case .toolGroup(_, let tools) = grouper.items[0] {
            XCTAssertEqual(tools.map(\.name), ["Read"])
        } else {
            XCTFail("Expected a Read tool group first")
        }
        if case .standaloneTool(_, let tool) = grouper.items[1] {
            XCTAssertEqual(tool.name, "Write")
        } else {
            XCTFail("Expected Write to be a standalone row")
        }
        if case .toolGroup(_, let tools) = grouper.items[2] {
            XCTAssertEqual(tools.map(\.name), ["Grep"])
        } else {
            XCTFail("Expected Grep to start a new tool group after Write")
        }
    }

    func testPromptToolResultIsSuppressedAndMarkPromptAnsweredPatchesPrompt() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let promptCall = ConversationEventRecord(
            id: "prompt-call",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: "{\"questions\":[{\"question\":\"Pick one\",\"options\":[{\"label\":\"A\",\"description\":\"First\"}]}]}"
        )
        let suppressedResult = ConversationEventRecord(
            id: "prompt-result",
            conversationId: conversationId,
            type: "tool_result",
            toolId: "prompt-1",
            toolOutput: "Answer questions?",
            isError: true
        )

        grouper.update(events: [promptCall, suppressedResult])
        grouper.markPromptAnswered(promptId: "prompt-1", summary: "A")

        XCTAssertEqual(grouper.items.count, 1)
        guard case .promptBlock(_, let prompt) = grouper.items[0] else {
            return XCTFail("Expected a prompt block")
        }
        XCTAssertEqual(prompt.id, "prompt-1")
        XCTAssertEqual(prompt.questions.first?.question, "Pick one")
        XCTAssertEqual(prompt.submittedSummary, "A")
    }

    func testAssistantMessageClosesGroupWhenAllToolsDone() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let toolCall = ConversationEventRecord(
            id: "call",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "g1",
            toolName: "Glob",
            toolInput: "{\"pattern\":\"**/AGENTS.md\"}"
        )
        let toolResult = ConversationEventRecord(
            id: "result",
            conversationId: conversationId,
            type: "tool_result",
            toolId: "g1",
            toolOutput: "no files"
        )
        let assistantMessage = ConversationEventRecord(
            id: "msg",
            conversationId: conversationId,
            type: "message",
            role: "assistant",
            content: "No AGENTS.md files exist."
        )

        grouper.update(events: [toolCall, toolResult, assistantMessage])

        // The Glob finished *before* the assistant message arrived, so the summary message
        // must sit below the completed group (summarizing), not above it.
        XCTAssertEqual(grouper.items.count, 2)
        guard case .toolGroup = grouper.items[0] else {
            return XCTFail("Expected the completed Glob group to come first")
        }
        guard case .assistantMessage(_, let text) = grouper.items[1] else {
            return XCTFail("Expected the assistant message to come after the group")
        }
        XCTAssertEqual(text, "No AGENTS.md files exist.")
    }

    func testAssistantMessageStaysAboveGroupWithInFlightTools() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let toolCall = ConversationEventRecord(
            id: "call",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "r1",
            toolName: "Read",
            toolInput: "{\"file_path\":\"a.swift\"}"
        )
        let assistantMessage = ConversationEventRecord(
            id: "msg",
            conversationId: conversationId,
            type: "message",
            role: "assistant",
            content: "Let me read the file."
        )

        grouper.update(events: [toolCall, assistantMessage])

        // The Read is still in flight when the message arrives (Claude is introducing the
        // next batch) — keep the group trailing the message so it can keep updating below.
        XCTAssertEqual(grouper.items.count, 2)
        guard case .assistantMessage = grouper.items[0] else {
            return XCTFail("Expected the assistant message above the in-flight group")
        }
        guard case .toolGroup = grouper.items[1] else {
            return XCTFail("Expected the still-running Read group to trail the message")
        }
    }

    func testConsecutiveGroupableToolsStayInSameGroup() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let firstCall = ConversationEventRecord(
            id: "call-1",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "r1",
            toolName: "Read",
            toolInput: "{\"file_path\":\"a.swift\"}"
        )
        let firstResult = ConversationEventRecord(
            id: "result-1",
            conversationId: conversationId,
            type: "tool_result",
            toolId: "r1",
            toolOutput: "ok"
        )
        let secondCall = ConversationEventRecord(
            id: "call-2",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "r2",
            toolName: "Read",
            toolInput: "{\"file_path\":\"b.swift\"}"
        )

        grouper.update(events: [firstCall, firstResult, secondCall])

        // Claude's stream serializes sequential Reads as call-result-call-result, so a
        // completion-triggered seal would fracture them into separate single-entry rows.
        // Keep them folded together; the group only closes on a non-groupable event.
        XCTAssertEqual(grouper.items.count, 1)
        guard case .toolGroup(_, let tools) = grouper.items[0] else {
            return XCTFail("Expected a single Read group")
        }
        XCTAssertEqual(tools.map(\.id), ["r1", "r2"])
    }

    func testSequentialAppendKeepsGroupableToolsInSameGroup() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let read1 = ConversationEventRecord(
            id: "call-1",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "r1",
            toolName: "Read",
            toolInput: "{\"file_path\":\"a.swift\"}"
        )
        let read2 = ConversationEventRecord(
            id: "call-2",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "r2",
            toolName: "Read",
            toolInput: "{\"file_path\":\"b.swift\"}"
        )

        grouper.append(event: read1)
        grouper.append(event: read2)

        // Streaming sends one event per append call. Before the fix, each groupable tool
        // produced its own single-entry `.toolGroup` because `flushGroup()` was clearing
        // pending state at the end of every append. They must fold into one open group
        // while streaming.
        XCTAssertEqual(grouper.items.count, 1)
        guard case .toolGroup(_, let tools) = grouper.items[0] else {
            return XCTFail("Expected a single open group holding both Reads")
        }
        XCTAssertEqual(tools.map(\.id), ["r1", "r2"])
    }

    func testClassificationRoutesMCPReadOnlyToGroupable() {
        XCTAssertEqual(ChatItemGrouper.groupability(forToolNamed: "Read"), .groupable)
        XCTAssertEqual(ChatItemGrouper.groupability(forToolNamed: "WebSearch"), .groupable)
        XCTAssertEqual(ChatItemGrouper.groupability(forToolNamed: "ToolSearch"), .groupable)
        XCTAssertEqual(ChatItemGrouper.groupability(forToolNamed: "Bash"), .standalone)
        XCTAssertEqual(ChatItemGrouper.groupability(forToolNamed: "Write"), .standalone)
        XCTAssertEqual(ChatItemGrouper.groupability(forToolNamed: "mcp__linear__search_issues"), .groupable)
        XCTAssertEqual(ChatItemGrouper.groupability(forToolNamed: "mcp__linear__list_projects"), .groupable)
        XCTAssertEqual(ChatItemGrouper.groupability(forToolNamed: "mcp__linear__create_issue"), .standalone)
        XCTAssertEqual(ChatItemGrouper.groupability(forToolNamed: "mcp__gdrive__update_file"), .standalone)
    }

    func testToolSearchSummaryStripsSelectPrefix() {
        let stripped = ChatItemGrouper.toolSummary(
            name: "ToolSearch",
            input: "{\"max_results\":1,\"query\":\"select:WebFetch\"}"
        )
        XCTAssertEqual(stripped, "Searching for tool `WebFetch`")

        let freeform = ChatItemGrouper.toolSummary(
            name: "ToolSearch",
            input: "{\"max_results\":5,\"query\":\"notebook jupyter\"}"
        )
        XCTAssertEqual(freeform, "Searching for tool `notebook jupyter`")
    }
}
