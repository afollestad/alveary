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
}
