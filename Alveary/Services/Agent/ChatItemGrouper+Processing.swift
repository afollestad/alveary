import Foundation

extension ChatItemGrouper {
    func process(_ event: ConversationEventRecord) {
        switch event.type {
        case "message" where event.role == "user":
            flushGroup()
            flushSubAgents()
            appendTranscriptItem(.userMessage(id: event.id, text: event.content ?? ""))
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
            appendTranscriptItem(.assistantMessage(id: event.id, text: event.content ?? ""))
        case "tool_call":
            handleToolCall(event)
        case "tool_result":
            handleToolResult(event)
        case "tool_approval":
            handleToolApproval(event)
        case "error":
            flushGroup()
            flushSubAgents()
            appendTranscriptItem(.error(id: event.id, message: event.content ?? "Unknown error"))
        case "stop" where ConversationInterruption.isDisplayMessage(event.content):
            flushGroup()
            flushSubAgents()
            appendTranscriptItem(.centeredNote(id: event.id, kind: .interrupted))
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

        appendTranscriptItem(.toolGroup(id: currentGroupId ?? UUID().uuidString, tools: pendingGroupTools))
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

    func handleTodoWriteToolCall(_ event: ConversationEventRecord) {
        flushGroup()
        currentTasks = parseTodoWriteInput(event.toolInput)
        let blockId = "tasks-\(event.toolId ?? event.id)"
        if replaceMatchingTaskListBlock(id: blockId, tasks: currentTasks) {
            return
        }
        appendTranscriptItem(.taskListBlock(id: blockId, tasks: currentTasks))
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

    func handleCenteredNoteToolCall(_ event: ConversationEventRecord) {
        guard let toolName = event.toolName,
              let noteKind = centeredTranscriptNoteKind(forToolNamed: toolName) else {
            return
        }

        let toolId = event.toolId ?? event.id
        centeredNoteToolKinds[toolId] = noteKind
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
            appendTranscriptItem(.standaloneTool(id: "tool-\(toolId)", tool: pendingTool))
        }
    }

    func handleToolApproval(_ event: ConversationEventRecord) {
        let toolUseId = event.toolId ?? event.id
        if let status = event.toolApprovalStatus.flatMap(ToolApprovalStatus.init(rawValue:)) {
            toolApprovalStatusesByToolId[toolUseId] = status
        }

        markEarlierPendingToolsComplete(excluding: toolUseId)

        if event.toolName == "AskUserQuestion" {
            return
        }

        flushGroup()
        flushSubAgents()
        appendTranscriptItem(
            .toolApproval(
                id: "approval-\(toolUseId)",
                approval: ToolApprovalRequest(
                    sessionId: event.content ?? "",
                    toolUseId: toolUseId,
                    toolName: event.toolName ?? "Tool",
                    toolInput: event.toolInput ?? "{}"
                ),
                status: event.toolApprovalStatus.flatMap(ToolApprovalStatus.init(rawValue:))
            )
        )
    }

    func handleCenteredNoteToolResult(
        toolId: String,
        kind: CenteredTranscriptNoteKind,
        event: ConversationEventRecord
    ) {
        if kind == .exitedPlanMode,
           toolApprovalStatusesByToolId[toolId] == .denied {
            flushGroup()
            flushSubAgents()
            appendTranscriptItem(.centeredNote(id: "note-\(toolId)", kind: .stayingInPlanMode))
            return
        }

        if event.isError {
            flushGroup()
            flushSubAgents()
            let pendingTool = makePendingToolEntry(id: toolId, event: ConversationEventRecord(
                id: toolId,
                conversationId: event.conversationId,
                type: "tool_call",
                toolId: toolId,
                toolName: centeredToolName(for: kind),
                toolInput: "{}"
            ))
            appendTranscriptItem(
                .standaloneTool(
                    id: "tool-\(toolId)",
                    tool: completedToolEntry(from: pendingTool, event: event)
                )
            )
            return
        }

        flushGroup()
        flushSubAgents()
        appendTranscriptItem(.centeredNote(id: "note-\(toolId)", kind: kind))
    }

    func centeredTranscriptNoteKind(forToolNamed toolName: String) -> CenteredTranscriptNoteKind? {
        switch toolName {
        case "EnterPlanMode":
            return .enteredPlanMode
        case "ExitPlanMode":
            return .exitedPlanMode
        default:
            return nil
        }
    }

    func centeredToolName(for kind: CenteredTranscriptNoteKind) -> String {
        switch kind {
        case .enteredPlanMode:
            return "EnterPlanMode"
        case .exitedPlanMode, .stayingInPlanMode:
            return "ExitPlanMode"
        case .interrupted:
            return "Tool"
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

    func replaceMatchingTaskListBlock(id: String, tasks: [TaskEntry]) -> Bool {
        guard let index = items.lastIndex(where: { $0.id == id }) else {
            return replaceTaskListBlockMatchingTasks(tasks)
        }
        items[index] = .taskListBlock(id: id, tasks: tasks)
        return true
    }

    func replaceTaskListBlockMatchingTasks(_ tasks: [TaskEntry]) -> Bool {
        guard let index = items.lastIndex(where: { item in
            if case .taskListBlock = item {
                return true
            }
            return false
        }),
              case .taskListBlock(let id, let existingTasks) = items[index],
              existingTasks.contains(where: { $0.status != .completed }),
              taskListsMatchByContent(existingTasks, tasks) else {
            return false
        }

        items[index] = .taskListBlock(id: id, tasks: tasks)
        return true
    }

    func taskListsMatchByContent(_ lhs: [TaskEntry], _ rhs: [TaskEntry]) -> Bool {
        let lhsContents = Set(lhs.map(\.normalizedContentForMatching).filter { !$0.isEmpty })
        let rhsContents = Set(rhs.map(\.normalizedContentForMatching).filter { !$0.isEmpty })
        guard !lhsContents.isEmpty, !rhsContents.isEmpty else {
            return false
        }

        let sharedCount = lhsContents.intersection(rhsContents).count
        let smallerCount = min(lhsContents.count, rhsContents.count)
        return sharedCount == smallerCount || sharedCount >= 2
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
        pendingGroupTools = pendingGroupTools.map { tool in
            guard tool.id != excludedToolId, !tool.isComplete else {
                return tool
            }
            return implicitlyCompletedToolEntry(from: tool)
        }

        for index in items.indices {
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
