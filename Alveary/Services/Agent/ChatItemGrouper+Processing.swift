import Foundation

extension ChatItemGrouper {
    func handleSubAgentControl(_ event: ConversationEvent) {
        switch event {
        case .subAgentStarted(let toolUseId, let description, let taskType):
            handleSubAgentStarted(id: toolUseId, description: description, taskType: taskType)
        case .subAgentProgress:
            handleSubAgentProgress(event)
        case .subAgentCompleted(let toolUseId, _, let toolUses, let totalTokens, let durationMs):
            handleSubAgentCompleted(
                id: toolUseId,
                toolUses: toolUses,
                totalTokens: totalTokens,
                durationMs: durationMs
            )
        default:
            break
        }
    }

    func routeSubAgentEventIfNeeded(_ event: ConversationEventRecord) -> Bool {
        if let parentToolUseId = event.parentToolUseId, activeSubAgents[parentToolUseId] != nil {
            routeToSubAgent(parentId: parentToolUseId, event: event)
            return true
        }

        if let parentToolUseId = event.parentToolUseId, evictedSubAgentIds.contains(parentToolUseId) {
            return true
        }

        return false
    }

    func process(_ event: ConversationEventRecord) {
        switch event.type {
        case "message" where event.role == "user":
            flushTools()
            flushSubAgents()
            items.append(.userMessage(id: event.id, text: event.content ?? ""))
        case "message" where event.role == "assistant":
            flushTools()
            flushSubAgents()
            items.append(.assistantMessage(id: event.id, text: event.content ?? ""))
        case "tool_call":
            handleToolCall(event)
        case "tool_result":
            handleToolResult(event)
        case "thinking":
            flushTools()
            items.append(.thinking(id: event.id, text: event.content ?? ""))
        case "error":
            flushTools()
            flushSubAgents()
            items.append(.error(id: event.id, message: event.content ?? "Unknown error"))
        default:
            break
        }
    }

    func resetAllState() {
        subAgentProgressRefreshTask?.cancel()
        subAgentProgressRefreshTask = nil
        items = []
        processedCount = 0
        pendingTools = []
        workingBlockId = nil
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
        if !pendingTools.isEmpty {
            removeLastRenderedWorkingBlockIfNeeded()
        }

        if !pendingSubAgentIds.isEmpty {
            removeLastRenderedSubAgentBlockIfNeeded()
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
        if let pendingIndex = pendingTools.firstIndex(where: { $0.id == toolId }) {
            pendingTools[pendingIndex] = updatedTool ?? pendingTools[pendingIndex]
            return
        }

        patchRenderedToolResult(id: toolId, entry: updatedTool)
    }

    func makeCompletedToolEntry(for toolId: String, event: ConversationEventRecord) -> ToolEntry? {
        if let pendingTool = pendingTools.first(where: { $0.id == toolId }) {
            return completedToolEntry(from: pendingTool, event: event)
        }

        return renderedToolEntry(for: toolId).map { tool in
            completedToolEntry(from: tool, event: event)
        }
    }

    func mutateSubAgent(id: String, _ mutate: (inout SubAgentEntry) -> Void) {
        guard var subAgent = activeSubAgents[id] else {
            return
        }

        mutate(&subAgent)
        activeSubAgents[id] = subAgent
    }

    func routeToSubAgent(parentId: String, event: ConversationEventRecord) {
        switch event.type {
        case "tool_call":
            let toolId = event.toolId ?? event.id
            mutateSubAgent(id: parentId) { subAgent in
                subAgent.tools.append(makePendingToolEntry(id: toolId, event: event))
            }
        case "tool_result":
            guard let toolId = event.toolId else {
                return
            }
            mutateSubAgent(id: parentId) { subAgent in
                guard let toolIndex = subAgent.tools.firstIndex(where: { $0.id == toolId }) else {
                    return
                }
                let tool = subAgent.tools[toolIndex]
                subAgent.tools[toolIndex] = completedToolEntry(from: tool, event: event)
            }
        default:
            break
        }
    }

    func flushTools() {
        guard !pendingTools.isEmpty else {
            return
        }

        items.append(.workingBlock(id: workingBlockId ?? UUID().uuidString, tools: pendingTools))
        pendingTools = []
        workingBlockId = nil
    }

    func flushSubAgents() {
        guard !pendingSubAgentIds.isEmpty else {
            return
        }

        let agents = pendingSubAgentIds.compactMap { activeSubAgents[$0] }
        if let firstAgent = agents.first {
            items.append(.subAgentBlock(id: "subagents-\(firstAgent.id)", agents: agents))
        }

        pendingSubAgentIds = pendingSubAgentIds.filter { id in
            guard subAgentIdsReadyForEviction.contains(id) else {
                return true
            }

            activeSubAgents.removeValue(forKey: id)
            subAgentIdsReadyForEviction.remove(id)
            evictedSubAgentIds.insert(id)
            return false
        }
    }

    func refreshLiveSubAgentBlock() {
        if !pendingSubAgentIds.isEmpty {
            removeLastRenderedSubAgentBlockIfNeeded()
        }
        flushSubAgents()
    }

    func scheduleSubAgentProgressRefresh() {
        subAgentProgressRefreshTask?.cancel()
        subAgentProgressRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else {
                return
            }
            refreshLiveSubAgentBlock()
        }
    }
}

private extension ChatItemGrouper {
    func handleSubAgentStarted(id: String, description: String, taskType: String?) {
        if activeSubAgents[id] == nil {
            activeSubAgents[id] = makeSubAgentEntry(
                id: id,
                agentType: normalizedAgentType(taskType),
                description: description
            )
            ensurePendingSubAgent(id: id)
        }

        subAgentProgressRefreshTask?.cancel()
        refreshLiveSubAgentBlock()
    }

    func handleSubAgentProgress(_ event: ConversationEvent) {
        guard case .subAgentProgress(
            let id,
            let description,
            let lastToolName,
            let toolUses,
            let totalTokens,
            let durationMs
        ) = event else {
            return
        }

        mutateSubAgent(id: id) { subAgent in
            subAgent.statusDescription = description
            subAgent.lastToolName = lastToolName
            subAgent.toolUseCount = toolUses
            subAgent.totalTokens = totalTokens
            subAgent.durationMs = durationMs
        }
        scheduleSubAgentProgressRefresh()
    }

    func handleSubAgentCompleted(id: String, toolUses: Int, totalTokens: Int, durationMs: Int) {
        mutateSubAgent(id: id) { subAgent in
            subAgent.isComplete = true
            subAgent.toolUseCount = toolUses
            subAgent.totalTokens = totalTokens
            subAgent.durationMs = durationMs
        }
        subAgentProgressRefreshTask?.cancel()
        refreshLiveSubAgentBlock()
    }

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
        flushTools()
        currentTasks = parseTodoWriteInput(event.toolInput)

        let blockId = taskListBlockId ?? "tasks-\(event.id)"
        taskListBlockId = blockId
        removeLastTaskListBlockIfNeeded()
        items.append(.taskListBlock(id: blockId, tasks: currentTasks))
    }

    func handleAskUserQuestionToolCall(_ event: ConversationEventRecord) {
        flushTools()
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

    func handleAgentToolCall(_ event: ConversationEventRecord) {
        flushTools()

        let toolId = event.toolId ?? event.id
        let parsedInput = parseAgentToolInput(event.toolInput)
        if activeSubAgents[toolId] != nil {
            mutateSubAgent(id: toolId) { subAgent in
                subAgent.agentType = parsedInput.agentType
                if !parsedInput.description.isEmpty {
                    subAgent.description = parsedInput.description
                }
            }
        } else if evictedSubAgentIds.contains(toolId) {
            patchRenderedSubAgentMetadata(
                id: toolId,
                agentType: parsedInput.agentType,
                description: parsedInput.description
            )
        } else {
            activeSubAgents[toolId] = makeSubAgentEntry(
                id: toolId,
                agentType: parsedInput.agentType,
                description: parsedInput.description
            )
        }

        ensurePendingSubAgent(id: toolId)
    }

    func handleGenericToolCall(_ event: ConversationEventRecord) {
        if workingBlockId == nil {
            workingBlockId = "work-\(event.id)"
        }

        let toolId = event.toolId ?? event.id
        pendingTools.append(makePendingToolEntry(id: toolId, event: event))
    }

    func handleSubAgentToolResult(toolId: String, event: ConversationEventRecord) -> Bool {
        if activeSubAgents[toolId] != nil {
            mutateSubAgent(id: toolId) { subAgent in
                subAgent.result = event.toolOutput ?? event.content
                subAgent.isComplete = true
            }
            subAgentIdsReadyForEviction.insert(toolId)
            return true
        }

        if evictedSubAgentIds.contains(toolId) {
            patchRenderedSubAgentResult(id: toolId, result: event.toolOutput ?? event.content)
            return true
        }

        return false
    }

    func makePendingToolEntry(id: String, event: ConversationEventRecord) -> ToolEntry {
        ToolEntry(
            id: id,
            name: event.toolName ?? "Tool",
            summary: cachedToolSummary(toolId: id, name: event.toolName, input: event.toolInput),
            input: event.toolInput ?? "{}",
            output: nil,
            stderr: nil,
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
            isInterrupted: event.toolOutputInterrupted,
            isImage: event.toolOutputIsImage,
            noOutputExpected: event.toolOutputNoOutputExpected,
            isError: event.isError
        )
    }

    func renderedToolEntry(for toolId: String) -> ToolEntry? {
        for item in items.reversed() {
            guard case .workingBlock(_, let tools) = item,
                  let tool = tools.first(where: { $0.id == toolId }) else {
                continue
            }
            return tool
        }

        return nil
    }

    func ensurePendingSubAgent(id: String) {
        if !pendingSubAgentIds.contains(id) {
            pendingSubAgentIds.append(id)
        }
    }

    func normalizedAgentType(_ taskType: String?) -> String {
        if taskType == nil || taskType == "local_agent" {
            return "general-purpose"
        }
        return taskType ?? "general-purpose"
    }

    func makeSubAgentEntry(id: String, agentType: String, description: String) -> SubAgentEntry {
        SubAgentEntry(
            id: id,
            agentType: agentType,
            description: description,
            tools: [],
            result: nil,
            isComplete: false,
            toolUseCount: 0
        )
    }

    func removeLastRenderedWorkingBlockIfNeeded() {
        if let index = items.lastIndex(where: { item in
            if case .workingBlock = item { return true }
            return false
        }) {
            items.remove(at: index)
        }
    }

    func removeLastRenderedSubAgentBlockIfNeeded() {
        if let index = items.lastIndex(where: { item in
            if case .subAgentBlock = item { return true }
            return false
        }) {
            items.remove(at: index)
        }
    }

    func patchRenderedSubAgentMetadata(id: String, agentType: String, description: String) {
        updateRenderedSubAgent(id: id) { agent in
            agent.agentType = agentType
            if !description.isEmpty {
                agent.description = description
            }
        }
    }

    func patchRenderedSubAgentResult(id: String, result: String?) {
        updateRenderedSubAgent(id: id) { agent in
            agent.result = result
        }
    }

    func updateRenderedSubAgent(id: String, mutate: (inout SubAgentEntry) -> Void) {
        for index in items.indices.reversed() {
            guard case .subAgentBlock(let blockId, var agents) = items[index],
                  let agentIndex = agents.firstIndex(where: { $0.id == id }) else {
                continue
            }

            mutate(&agents[agentIndex])
            items[index] = .subAgentBlock(id: blockId, agents: agents)
            return
        }
    }

    func patchRenderedToolResult(id: String, entry: ToolEntry?) {
        guard let entry else {
            return
        }

        for index in items.indices.reversed() {
            guard case .workingBlock(let blockId, var tools) = items[index],
                  let toolIndex = tools.firstIndex(where: { $0.id == id }) else {
                continue
            }

            tools[toolIndex] = entry
            items[index] = .workingBlock(id: blockId, tools: tools)
            return
        }
    }
}
