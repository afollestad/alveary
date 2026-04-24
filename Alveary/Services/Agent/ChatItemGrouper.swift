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
    case toolApproval(id: String, approval: ToolApprovalRequest, status: ToolApprovalStatus?)
    case toolApprovalBatch(id: String, approvals: [ToolApprovalRequest], status: ToolApprovalStatus?)
    case centeredNote(id: String, kind: CenteredTranscriptNoteKind)
    case error(id: String, message: String)

    var id: String {
        switch self {
        case .userMessage(let id, _), .assistantMessage(let id, _), .toolGroup(let id, _),
             .standaloneTool(let id, _), .subAgentBlock(let id, _), .taskListBlock(let id, _),
             .promptBlock(let id, _), .toolApproval(let id, _, _), .toolApprovalBatch(let id, _, _),
             .centeredNote(let id, _), .error(let id, _):
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
        if case .centeredNote(_, .interrupted) = self {
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
        let allowsCustomResponse: Bool

        init(
            question: String,
            header: String?,
            options: [PromptOption],
            multiSelect: Bool,
            allowsCustomResponse: Bool = true
        ) {
            self.question = question
            self.header = header
            self.options = options
            self.multiSelect = multiSelect
            self.allowsCustomResponse = allowsCustomResponse
        }

        var renderedOptions: [PromptOption] {
            if options.contains(where: \.isCustomResponse) {
                return options
            }
            guard allowsCustomResponse else {
                return options
            }
            return options + [.other]
        }
    }

    struct PromptOption: Equatable {
        static let customResponseID = "__other__"

        let id: String
        let label: String
        let description: String
        let isCustomResponse: Bool

        init(
            id: String? = nil,
            label: String,
            description: String,
            isCustomResponse: Bool = false
        ) {
            self.id = id ?? label
            self.label = label
            self.description = description
            self.isCustomResponse = isCustomResponse
        }

        static let other = PromptOption(
            id: customResponseID,
            label: "Other",
            description: "Write your own response.",
            isCustomResponse: true
        )
    }
}

enum CenteredTranscriptNoteKind: Equatable {
    case interrupted
    case enteredPlanMode
    case exitedPlanMode
    case stayingInPlanMode

    var text: String {
        switch self {
        case .interrupted:
            return "Interrupted"
        case .enteredPlanMode:
            return "Entered plan mode"
        case .exitedPlanMode:
            return "Exited plan mode"
        case .stayingInPlanMode:
            return "Staying in plan mode"
        }
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

struct ToolApprovalBatchState: Equatable {
    let itemId: String
    let sessionId: String
    let status: ToolApprovalStatus?
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
    var centeredNoteToolKinds: [String: CenteredTranscriptNoteKind] = [:]
    var toolApprovalStatusesByToolId: [String: ToolApprovalStatus] = [:]
    var currentToolApprovalBatch: ToolApprovalBatchState?
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
        centeredNoteToolKinds = [:]
        toolApprovalStatusesByToolId = [:]
        currentToolApprovalBatch = nil
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

    func replaceExistingPromptIfPresent(with prompt: PromptEntry) -> Bool {
        guard let index = items.lastIndex(where: { item in
            guard case .promptBlock(_, let existingPrompt) = item else {
                return false
            }
            return existingPrompt.id == prompt.id
        }), case .promptBlock(let itemID, let existingPrompt) = items[index] else {
            return false
        }

        items[index] = .promptBlock(
            id: itemID,
            prompt: PromptEntry(
                id: prompt.id,
                questions: prompt.questions,
                submittedSummary: prompt.submittedSummary ?? existingPrompt.submittedSummary
            )
        )
        return true
    }

    func ignoreDuplicateAnsweredPromptReplay(_ prompt: PromptEntry) -> Bool {
        guard let index = items.lastIndex(where: { item in
            guard case .promptBlock(_, let existingPrompt) = item else {
                return false
            }
            return existingPrompt.questions == prompt.questions &&
                existingPrompt.submittedSummary != nil
        }) else {
            return false
        }

        let laterItems = items[items.index(after: index)...]
        let hasLaterUserMessage = laterItems.contains { item in
            if case .userMessage = item {
                return true
            }
            return false
        }

        return !hasLaterUserMessage
    }

    func replaceLatestUnansweredPrompt(with prompt: PromptEntry) -> Bool {
        guard let index = items.lastIndex(where: { item in
            guard case .promptBlock(_, let existingPrompt) = item else {
                return false
            }
            return existingPrompt.submittedSummary == nil
        }) else {
            return false
        }

        let itemID = items[index].id
        items.removeSubrange(items.index(after: index)..<items.endIndex)
        items[index] = .promptBlock(
            id: itemID,
            prompt: prompt
        )
        return true
    }

    var hasUnansweredPrompt: Bool {
        items.contains { item in
            guard case .promptBlock(_, let prompt) = item else {
                return false
            }
            return prompt.submittedSummary == nil
        }
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
