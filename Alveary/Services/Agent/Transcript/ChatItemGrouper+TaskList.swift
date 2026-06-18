import AgentCLIKit
import Foundation

extension ChatItemGrouper {
    func handleTodoWriteToolCall(_ event: ConversationEventRecord) {
        flushGroup()
        currentTasks = parseTodoWriteInput(event.toolInput)
        let blockId = "tasks-\(event.toolId ?? event.id)"
        if replaceMatchingTaskListBlock(id: blockId, tasks: currentTasks) {
            return
        }
        appendTranscriptItem(.taskListBlock(id: blockId, tasks: currentTasks))
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

    func handleAgentTaskToolCallIfNeeded(_ event: ConversationEventRecord) -> Bool {
        let envelope = agentTaskToolCallEnvelope(from: event)
        if AgentTaskListReducer.isTaskToolDiscovery(envelope) {
            hiddenAgentTaskToolSearchIds.insert(event.toolId ?? event.id)
            return true
        }

        guard let toolName = event.toolName,
              AgentTaskListReducer.isTaskToolName(toolName) else {
            return false
        }

        agentTaskToolIds.insert(event.toolId ?? event.id)
        if let snapshot = agentTaskListReducer.append(envelope) {
            renderAgentTaskListSnapshot(snapshot)
        }
        return true
    }

    func handleAgentTaskToolResultIfNeeded(_ event: ConversationEventRecord) -> Bool {
        guard let toolId = event.toolId else {
            return false
        }

        if hiddenAgentTaskToolSearchIds.remove(toolId) != nil {
            return true
        }

        guard agentTaskToolIds.contains(toolId) else {
            return false
        }

        if let snapshot = agentTaskListReducer.append(agentTaskToolResultEnvelope(from: event)) {
            renderAgentTaskListSnapshot(snapshot)
        }
        agentTaskToolIds.remove(toolId)
        return true
    }

    func handleTaskListSnapshot(_ event: ConversationEventRecord) {
        guard let snapshot = ConversationTaskListSnapshot.decoded(from: event) else {
            return
        }
        renderTaskListSnapshot(snapshot)
    }

    func renderAgentTaskListSnapshot(_ snapshot: AgentTaskListSnapshot) {
        flushGroup()
        currentTasks = snapshot.items.map(\.taskEntry)
        if replaceMatchingTaskListBlock(id: snapshot.id, tasks: currentTasks) {
            return
        }
        appendTranscriptItem(.taskListBlock(id: snapshot.id, tasks: currentTasks))
    }

    func renderTaskListSnapshot(_ snapshot: ConversationTaskListSnapshot) {
        flushGroup()
        currentTasks = snapshot.items.map(\.taskEntry)
        if replaceMatchingTaskListBlock(id: snapshot.id, tasks: currentTasks) {
            return
        }
        appendTranscriptItem(.taskListBlock(id: snapshot.id, tasks: currentTasks))
    }

    func agentTaskToolCallEnvelope(from event: ConversationEventRecord) -> AgentEventEnvelope {
        AgentEventEnvelope(
            generation: 0,
            index: processedCount,
            providerId: .claude,
            conversationId: AgentConversationID(rawValue: event.conversationId),
            providerSessionId: nil,
            source: .stdout,
            event: .toolCall(AgentToolCallEvent(
                id: event.toolId ?? event.id,
                name: event.toolName ?? "Tool",
                input: agentTaskJSONValue(from: event.toolInput)
            )),
            createdAt: event.timestamp
        )
    }

    func agentTaskToolResultEnvelope(from event: ConversationEventRecord) -> AgentEventEnvelope {
        AgentEventEnvelope(
            generation: 0,
            index: processedCount,
            providerId: .claude,
            conversationId: AgentConversationID(rawValue: event.conversationId),
            providerSessionId: nil,
            source: .stdout,
            event: .toolResult(AgentToolResultEvent(
                id: event.toolId ?? event.id,
                isError: event.isError,
                content: event.toolOutput ?? event.content ?? "",
                metadata: [:]
            )),
            createdAt: event.timestamp
        )
    }

    func agentTaskJSONValue(from input: String?) -> AgentCLIKit.JSONValue {
        guard let input,
              let data = input.data(using: .utf8),
              let value = try? JSONDecoder().decode(AgentCLIKit.JSONValue.self, from: data) else {
            return .object([:])
        }
        return value
    }
}

private extension AgentTaskListItem {
    var taskEntry: TaskEntry {
        TaskEntry(
            id: id,
            content: subject,
            activeForm: activeForm,
            status: status.taskEntryStatus
        )
    }
}

private extension ConversationTaskListItem {
    var taskEntry: TaskEntry {
        TaskEntry(
            id: id,
            content: content,
            activeForm: activeForm,
            status: status.taskEntryStatus
        )
    }
}

private extension AgentTaskListItem.Status {
    var taskEntryStatus: TaskEntry.Status {
        switch self {
        case .pending:
            return .pending
        case .inProgress:
            return .inProgress
        case .completed:
            return .completed
        }
    }
}

private extension ConversationTaskListStatus {
    var taskEntryStatus: TaskEntry.Status {
        switch self {
        case .pending:
            return .pending
        case .inProgress:
            return .inProgress
        case .completed:
            return .completed
        }
    }
}
