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

    func handleAgentToolCall(_ event: ConversationEventRecord) {
        flushGroup()

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

    func removeLastRenderedSubAgentBlockIfNeeded() {
        if let index = items.lastIndex(where: { item in
            if case .subAgentBlock = item { return true }
            return false
        }) {
            items.remove(at: index)
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
}
