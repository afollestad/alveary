import Foundation

extension ChatItemGrouper {
    func process(_ event: ConversationEventRecord) {
        switch event.type {
        case "message" where event.role == "user":
            currentToolApprovalBatch = nil
            flushGroup()
            flushSubAgents()
            appendTranscriptItem(.userMessage(id: event.id, text: event.content ?? ""))
        case "message" where event.role == "assistant":
            currentToolApprovalBatch = nil
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
            appendTranscriptItem(.assistantMessage(id: event.id, text: event.content ?? ""))
        case "tool_call":
            handleToolCall(event)
        case "tool_result":
            handleToolResult(event)
        case "tool_approval":
            handleToolApproval(event)
        case "error":
            currentToolApprovalBatch = nil
            flushGroup()
            flushSubAgents()
            appendTranscriptItem(.error(id: event.id, message: event.content ?? "Unknown error"))
        case "stop" where ConversationInterruption.isDisplayMessage(event.content):
            currentToolApprovalBatch = nil
            flushGroup()
            flushSubAgents()
            appendTranscriptItem(.centeredNote(id: event.id, kind: .interrupted))
        case "stop" where ConversationSessionHandoff.isDisplayMessage(event.content):
            currentToolApprovalBatch = nil
            flushGroup()
            flushSubAgents()
            appendTranscriptItem(.centeredNote(id: event.id, kind: .sessionHandoff))
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
        promptToolIds = []
        centeredNoteToolKinds = [:]
        toolApprovalStatusesByToolId = [:]
        currentToolApprovalBatch = nil
    }

    func removeTrailingPendingBlocksIfNeeded() {
        if !pendingGroupTools.isEmpty {
            removeLastRenderedGroupIfNeeded()
        }

        // Sub-agent blocks replace/merge themselves in place because approval
        // prompts can be interleaved beneath a live parallel-agent block.
    }

    func flushGroup() {
        guard !pendingGroupTools.isEmpty else {
            return
        }

        appendTranscriptItem(.toolGroup(id: currentGroupId ?? UUID().uuidString, tools: pendingGroupTools))
        pendingGroupTools = []
        currentGroupId = nil
    }

    func handleToolResult(_ event: ConversationEventRecord) {
        currentToolApprovalBatch = nil

        guard let toolId = event.toolId else {
            return
        }
        guard !promptToolIds.contains(toolId) else {
            return
        }
        if let centeredNoteKind = centeredNoteToolKinds.removeValue(forKey: toolId) {
            handleCenteredNoteToolResult(toolId: toolId, kind: centeredNoteKind, event: event)
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
        case "EnterPlanMode", "ExitPlanMode":
            handleCenteredNoteToolCall(event)
        case "Agent":
            handleAgentToolCall(event)
        default:
            handleGenericToolCall(event)
        }
    }

    func handleAskUserQuestionToolCall(_ event: ConversationEventRecord) {
        flushGroup()
        flushSubAgents()

        let toolId = event.toolId ?? event.id
        promptToolIds.insert(toolId)
        let prompt = PromptEntry(
            id: toolId,
            questions: parseAskUserQuestionInput(event.toolInput),
            submittedSummary: event.content?.isEmpty == false ? event.content : nil
        )
        if replaceExistingPromptIfPresent(with: prompt) {
            return
        }
        if ignoreDuplicateAnsweredPromptReplay(prompt) {
            return
        }
        if replaceLatestUnansweredPrompt(with: prompt) {
            return
        }

        appendTranscriptItem(
            .promptBlock(
                id: "prompt-\(toolId)",
                prompt: prompt
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
            if appendStandaloneToolToCurrentApprovalBatchIfNeeded(pendingTool) {
                return
            }
            appendTranscriptItem(.standaloneTool(id: "tool-\(toolId)", tool: pendingTool))
        }
    }

    func handleToolApproval(_ event: ConversationEventRecord) {
        let toolUseId = event.toolId ?? event.id
        if let status = event.toolApprovalStatus.flatMap(ToolApprovalStatus.init(rawValue:)) {
            toolApprovalStatusesByToolId[toolUseId] = status
        }

        if currentToolApprovalBatch?.sessionId != event.content {
            markEarlierPendingToolsComplete(excluding: toolUseId)
        }

        if event.toolName == "AskUserQuestion" {
            return
        }

        flushGroup()
        flushSubAgents()
        appendToolApproval(
            ToolApprovalRequest(
                sessionId: event.content ?? "",
                toolUseId: toolUseId,
                toolName: event.toolName ?? "Tool",
                toolInput: event.toolInput ?? "{}"
            ),
            status: event.toolApprovalStatus.flatMap(ToolApprovalStatus.init(rawValue:))
        )
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

    func markEarlierPendingToolsComplete(excluding excludedToolId: String) {
        markEarlierPendingGroupToolsComplete(excluding: excludedToolId)

        let upperBound = renderedItemIndex(containingToolId: excludedToolId) ?? items.endIndex
        for index in items[..<upperBound].indices {
            switch items[index] {
            case .toolGroup(let blockId, let tools):
                let updatedTools = tools.map { tool in
                    guard tool.id != excludedToolId, !tool.isComplete else {
                        return tool
                    }
                    return implicitlyCompletedToolEntry(from: tool)
                }
                if updatedTools != tools {
                    items[index] = .toolGroup(id: blockId, tools: updatedTools)
                }
            case .standaloneTool(let rowId, let tool):
                guard tool.id != excludedToolId, !tool.isComplete else {
                    continue
                }
                items[index] = .standaloneTool(id: rowId, tool: implicitlyCompletedToolEntry(from: tool))
            default:
                continue
            }
        }
    }

    func markEarlierPendingGroupToolsComplete(excluding excludedToolId: String) {
        let upperBound = pendingGroupTools.firstIndex(where: { $0.id == excludedToolId }) ?? pendingGroupTools.endIndex
        for index in pendingGroupTools[..<upperBound].indices {
            let tool = pendingGroupTools[index]
            guard !tool.isComplete else {
                continue
            }
            pendingGroupTools[index] = implicitlyCompletedToolEntry(from: tool)
        }
    }

    func renderedItemIndex(containingToolId toolId: String) -> Array<ChatItem>.Index? {
        items.firstIndex { item in
            switch item {
            case .toolGroup(_, let tools):
                tools.contains { $0.id == toolId }
            case .standaloneTool(_, let tool):
                tool.id == toolId
            default:
                false
            }
        }
    }

    func implicitlyCompletedToolEntry(from tool: ToolEntry) -> ToolEntry {
        ToolEntry(
            id: tool.id,
            name: tool.name,
            summary: tool.summary,
            input: tool.input,
            output: tool.output,
            stderr: tool.stderr,
            isComplete: true,
            isInterrupted: tool.isInterrupted,
            isImage: tool.isImage,
            noOutputExpected: tool.noOutputExpected,
            isError: tool.isError
        )
    }
}
