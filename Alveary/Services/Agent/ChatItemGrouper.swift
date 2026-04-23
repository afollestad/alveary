import Foundation
import Observation

enum ChatItem: Identifiable, Equatable {
    case userMessage(id: String, text: String)
    case assistantMessage(id: String, text: String)
    case toolGroup(id: String, tools: [ToolEntry])
    case standaloneTool(id: String, tool: ToolEntry)
    case subAgentBlock(id: String, agents: [SubAgentEntry])
    case taskListBlock(id: String, tasks: [TaskEntry])
    case promptBlock(id: String, prompt: PromptEntry)
    case toolApproval(id: String, approval: ToolApprovalRequest)
    case turnInterruptedNote(id: String)
    case error(id: String, message: String)

    var id: String {
        switch self {
        case .userMessage(let id, _), .assistantMessage(let id, _), .toolGroup(let id, _),
             .standaloneTool(let id, _), .subAgentBlock(let id, _), .taskListBlock(let id, _),
             .promptBlock(let id, _), .toolApproval(let id, _), .turnInterruptedNote(let id), .error(let id, _):
            id
        }
    }

    var isUserMessage: Bool {
        if case .userMessage = self {
            return true
        }
        return false
    }

    var isTurnInterruptedNote: Bool {
        if case .turnInterruptedNote = self {
            return true
        }
        return false
    }
}

extension [ChatItem] {
    var hasInterruptedNoteAfterLatestUserMessage: Bool {
        let latestUserIndex = lastIndex(where: \.isUserMessage)
        let searchStart = latestUserIndex.map { index(after: $0) } ?? startIndex
        return self[searchStart...].contains(where: \.isTurnInterruptedNote)
    }
}

struct PromptEntry: Identifiable, Equatable {
    let id: String
    let questions: [PromptQuestion]
    let submittedSummary: String?

    struct PromptQuestion: Equatable {
        let question: String
        let header: String?
        let options: [PromptOption]
        let multiSelect: Bool
    }

    struct PromptOption: Equatable {
        let label: String
        let description: String
    }
}

struct ToolEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String
    let input: String
    let output: String?
    let stderr: String?
    let isComplete: Bool
    let isInterrupted: Bool
    let isImage: Bool
    let noOutputExpected: Bool
    let isError: Bool
}

struct SubAgentEntry: Identifiable, Equatable {
    let id: String
    var agentType: String
    var description: String
    var statusDescription: String?
    var lastToolName: String?
    var tools: [ToolEntry]
    var result: String?
    var isComplete: Bool
    var toolUseCount: Int
    var totalTokens: Int = 0
    var durationMs: Int = 0
}

struct TaskEntry: Identifiable, Equatable {
    let id: String
    let content: String
    let activeForm: String?
    var status: Status

    enum Status: String, Equatable {
        case pending
        case inProgress = "in_progress"
        case completed
    }
}

extension TaskEntry {
    var normalizedContentForMatching: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

@MainActor
@Observable
final class ChatItemGrouper {
    var items: [ChatItem] = []
    var processedCount = 0
    var pendingGroupTools: [ToolEntry] = []
    var currentGroupId: String?
    var summaryCache: [String: String] = [:]
    var activeSubAgents: [String: SubAgentEntry] = [:]
    var pendingSubAgentIds: [String] = []
    var subAgentIdsReadyForEviction: Set<String> = []
    var evictedSubAgentIds: Set<String> = []
    var currentTasks: [TaskEntry] = []
    var promptToolIds: Set<String> = []
    var subAgentProgressRefreshTask: Task<Void, Never>?

    func append(event: ConversationEventRecord) {
        removeTrailingPendingBlocksIfNeeded()

        if !routeSubAgentEventIfNeeded(event) {
            process(event)
        }

        reemitPendingGroup()
        flushSubAgents()
        processedCount += 1
    }

    func update(events: [ConversationEventRecord], forceFullRebuild: Bool = false) {
        if forceFullRebuild || events.count < processedCount {
            resetAllState()
        }

        removeTrailingPendingBlocksIfNeeded()

        for event in events[processedCount...] {
            if routeSubAgentEventIfNeeded(event) {
                continue
            }
            process(event)
        }

        reemitPendingGroup()
        flushSubAgents()
        processedCount = events.count
    }

    /// Re-emit the in-flight group without clearing it. Called at the end of every
    /// `append` / `update` cycle so the UI reflects the latest pending tools; the group
    /// stays open so subsequent events keep folding into it. Close paths still use
    /// `flushGroup()` to emit *and* clear.
    func reemitPendingGroup() {
        guard !pendingGroupTools.isEmpty else {
            return
        }
        appendTranscriptItem(.toolGroup(id: currentGroupId ?? UUID().uuidString, tools: pendingGroupTools))
    }

    func resetInFlightStateForNewSession() {
        subAgentProgressRefreshTask?.cancel()
        subAgentProgressRefreshTask = nil
        pendingGroupTools = []
        currentGroupId = nil
        summaryCache = [:]
        activeSubAgents = [:]
        pendingSubAgentIds = []
        subAgentIdsReadyForEviction = []
        evictedSubAgentIds = []
        promptToolIds = []
    }

    func markPromptAnswered(promptId: String, summary: String) {
        guard let index = items.lastIndex(where: { item in
            guard case .promptBlock(_, let prompt) = item else {
                return false
            }
            return prompt.id == promptId
        }), case .promptBlock(let id, let prompt) = items[index] else {
            return
        }

        items[index] = .promptBlock(
            id: id,
            prompt: PromptEntry(
                id: prompt.id,
                questions: prompt.questions,
                submittedSummary: summary
            )
        )
    }

    func appendLocalUserMessage(id: String, text: String) {
        flushGroup()
        flushSubAgents()
        appendTranscriptItem(.userMessage(id: id, text: text))
        processedCount += 1
    }

    func appendTranscriptItem(_ item: ChatItem) {
        guard !item.isTaskListBlock,
              let latestTaskListIndex = items.lastIndex(where: \.isTaskListBlock),
              items[latestTaskListIndex].isIncompleteTaskListBlock else {
            items.append(item)
            return
        }

        items.insert(item, at: latestTaskListIndex)
    }
}

private extension ChatItem {
    var isTaskListBlock: Bool {
        if case .taskListBlock = self {
            return true
        }
        return false
    }

    var isIncompleteTaskListBlock: Bool {
        guard case .taskListBlock(_, let tasks) = self else {
            return false
        }
        return tasks.contains { $0.status != .completed }
    }
}
