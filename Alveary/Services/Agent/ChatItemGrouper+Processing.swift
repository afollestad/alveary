import Foundation

extension ChatItemGrouper {
    func process(_ event: ConversationEventRecord) {
        switch event.type {
        case "message" where event.role == "user":
            flushGroup()
            flushSubAgents()
            items.append(.userMessage(id: event.id, text: event.content ?? ""))
        case "message" where event.role == "assistant":
            flushSubAgents()
            // When every tool in the open group has already produced a result, the
            // assistant message is summarizing the completed batch and should sit *below*
            // the group. Close the group first. When some tools are still running, Claude
            // is introducing the next batch mid-stream — leave the group open so the
            // trailing `.toolGroup` (stripped by `removeTrailingPendingBlocksIfNeeded`)
            // gets re-emitted by the outer `flushGroup()` *below* the message.
            if pendingGroupTools.allSatisfy(\.isComplete) {
                flushGroup()
            }
            items.append(.assistantMessage(id: event.id, text: event.content ?? ""))
        case "tool_call":
            handleToolCall(event)
        case "tool_result":
            handleToolResult(event)
        case "error":
            flushGroup()
            flushSubAgents()
            items.append(.error(id: event.id, message: event.content ?? "Unknown error"))
        case "stop" where ConversationInterruption.isDisplayMessage(event.content):
            flushGroup()
            flushSubAgents()
            items.append(.turnInterruptedNote(id: event.id))
        default:
            // `thinking` events are intentionally not rendered — they add little for the
            // user and clutter transcripts. The active-turn "Thinking…" spinner in
            // `ChatTranscriptView` covers the "something is happening" affordance.
            break
        }
    }

    func resetAllState() {
        subAgentProgressRefreshTask?.cancel()
        subAgentProgressRefreshTask = nil
        items = []
        processedCount = 0
        pendingGroupTools = []
        currentGroupId = nil
        summaryCache = [:]
        activeSubAgents = [:]
        pendingSubAgentIds = []
        subAgentIdsReadyForEviction = []
        evictedSubAgentIds = []
        currentTasks = []
        taskListBlockId = nil
        promptToolIds = []
    }

    func removeTrailingPendingBlocksIfNeeded() {
        if !pendingGroupTools.isEmpty {
            removeLastRenderedGroupIfNeeded()
        }

        if !pendingSubAgentIds.isEmpty {
            removeLastRenderedSubAgentBlockIfNeeded()
        }
    }

    func flushGroup() {
        guard !pendingGroupTools.isEmpty else {
            return
        }

        items.append(.toolGroup(id: currentGroupId ?? UUID().uuidString, tools: pendingGroupTools))
        pendingGroupTools = []
        currentGroupId = nil
    }

    func handleToolResult(_ event: ConversationEventRecord) {
        guard let toolId = event.toolId else {
            return
        }
        guard !promptToolIds.contains(toolId) else {
            return
        }
        guard !handleSubAgentToolResult(toolId: toolId, event: event) else {
            return
        }

        let updatedTool = makeCompletedToolEntry(for: toolId, event: event)
        if let pendingIndex = pendingGroupTools.firstIndex(where: { $0.id == toolId }) {
            if let updatedTool {
                pendingGroupTools[pendingIndex] = updatedTool
            }
            return
        }

        patchRenderedToolResult(id: toolId, entry: updatedTool)
    }

    func makePendingToolEntry(id: String, event: ConversationEventRecord) -> ToolEntry {
        ToolEntry(
            id: id,
            name: event.toolName ?? "Tool",
            summary: cachedToolSummary(toolId: id, name: event.toolName, input: event.toolInput),
            input: event.toolInput ?? "{}",
            output: nil,
            stderr: nil,
            isComplete: false,
            isInterrupted: false,
            isImage: false,
            noOutputExpected: false,
            isError: false
        )
    }

    func completedToolEntry(from tool: ToolEntry, event: ConversationEventRecord) -> ToolEntry {
        ToolEntry(
            id: tool.id,
            name: tool.name,
            summary: tool.summary,
            input: tool.input,
            output: event.toolOutput ?? event.content,
            stderr: event.toolOutputStderr,
            isComplete: true,
            isInterrupted: event.toolOutputInterrupted,
            isImage: event.toolOutputIsImage,
            noOutputExpected: event.toolOutputNoOutputExpected,
            isError: event.isError
        )
    }
}

private extension ChatItemGrouper {
    func handleToolCall(_ event: ConversationEventRecord) {
        switch event.toolName {
        case "TodoWrite":
            handleTodoWriteToolCall(event)
        case "AskUserQuestion":
            handleAskUserQuestionToolCall(event)
        case "Agent":
            handleAgentToolCall(event)
        default:
            handleGenericToolCall(event)
        }
    }

    func handleTodoWriteToolCall(_ event: ConversationEventRecord) {
        flushGroup()
        currentTasks = parseTodoWriteInput(event.toolInput)

        let blockId = taskListBlockId ?? "tasks-\(event.id)"
        taskListBlockId = blockId
        removeLastTaskListBlockIfNeeded()
        items.append(.taskListBlock(id: blockId, tasks: currentTasks))
    }

    func handleAskUserQuestionToolCall(_ event: ConversationEventRecord) {
        flushGroup()
        flushSubAgents()

        let toolId = event.toolId ?? event.id
        promptToolIds.insert(toolId)
        items.append(
            .promptBlock(
                id: "prompt-\(toolId)",
                prompt: PromptEntry(
                    id: toolId,
                    questions: parseAskUserQuestionInput(event.toolInput),
                    submittedSummary: event.content?.isEmpty == false ? event.content : nil
                )
            )
        )
    }

    func handleGenericToolCall(_ event: ConversationEventRecord) {
        let toolName = event.toolName ?? "Tool"
        let toolId = event.toolId ?? event.id
        let pendingTool = makePendingToolEntry(id: toolId, event: event)

        switch ChatItemGrouper.groupability(forToolNamed: toolName) {
        case .groupable:
            ensureCurrentGroupId(seed: event.id)
            pendingGroupTools.append(pendingTool)
        case .standalone:
            flushGroup()
            items.append(.standaloneTool(id: "tool-\(toolId)", tool: pendingTool))
        }
    }

    func removeLastTaskListBlockIfNeeded() {
        if let index = items.lastIndex(where: { item in
            if case .taskListBlock = item { return true }
            return false
        }) {
            items.remove(at: index)
        }
    }

    func makeCompletedToolEntry(for toolId: String, event: ConversationEventRecord) -> ToolEntry? {
        if let pendingTool = pendingGroupTools.first(where: { $0.id == toolId }) {
            return completedToolEntry(from: pendingTool, event: event)
        }

        return renderedToolEntry(for: toolId).map { tool in
            completedToolEntry(from: tool, event: event)
        }
    }

    func renderedToolEntry(for toolId: String) -> ToolEntry? {
        for item in items.reversed() {
            switch item {
            case .toolGroup(_, let tools):
                if let tool = tools.first(where: { $0.id == toolId }) {
                    return tool
                }
            case .standaloneTool(_, let tool) where tool.id == toolId:
                return tool
            default:
                continue
            }
        }

        return nil
    }

    func ensureCurrentGroupId(seed: String) {
        if currentGroupId == nil {
            currentGroupId = "group-\(seed)"
        }
    }

    func removeLastRenderedGroupIfNeeded() {
        if let index = items.lastIndex(where: { item in
            if case .toolGroup = item { return true }
            return false
        }) {
            items.remove(at: index)
        }
    }

    func patchRenderedToolResult(id: String, entry: ToolEntry?) {
        guard let entry else {
            return
        }

        for index in items.indices.reversed() {
            switch items[index] {
            case .toolGroup(let blockId, var tools):
                guard let toolIndex = tools.firstIndex(where: { $0.id == id }) else {
                    continue
                }
                tools[toolIndex] = entry
                items[index] = .toolGroup(id: blockId, tools: tools)
                return
            case .standaloneTool(let rowId, let tool) where tool.id == id:
                items[index] = .standaloneTool(id: rowId, tool: entry)
                return
            default:
                continue
            }
        }
    }
}
