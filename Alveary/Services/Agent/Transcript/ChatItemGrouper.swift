import AgentCLIKit
import Foundation
import Observation

@MainActor
@Observable
final class ChatItemGrouper {
    static let handledPromptSummary = "Response already handled."

    var items: [ChatItem] = []
    var processedCount = 0
    var pendingGroupTools: [ToolEntry] = []
    var currentGroupId: String?
    var summaryCache: [String: String] = [:]
    var activeSubAgents: [String: SubAgentEntry] = [:]
    var pendingSubAgentIds: [String] = []
    var subAgentIdsReadyForEviction: Set<String> = []
    var evictedSubAgentIds: Set<String> = []
    var pendingSubAgentCompletions: [String: PendingSubAgentCompletion] = [:]
    var pendingSubAgentResults: [String: ConversationEventRecord] = [:]
    var currentTasks: [TaskEntry] = []
    var agentTaskListReducer = AgentTaskListReducer()
    var agentTaskToolIds: Set<String> = []
    var hiddenAgentTaskToolSearchIds: Set<String> = []
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
        pendingSubAgentCompletions = [:]
        pendingSubAgentResults = [:]
        agentTaskListReducer = AgentTaskListReducer()
        agentTaskToolIds = []
        hiddenAgentTaskToolSearchIds = []
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

    func markLatestUnansweredPromptHandledAfterContinuationIfNeeded() {
        guard let index = items.lastIndex(where: { item in
            guard case .promptBlock(_, let prompt) = item else {
                return false
            }
            return prompt.submittedSummary == nil
        }), case .promptBlock(let id, let prompt) = items[index] else {
            return
        }
        let laterItems = items[items.index(after: index)...]
        guard laterItems.contains(where: \.isAssistantMessage) else {
            return
        }

        items[index] = .promptBlock(
            id: id,
            prompt: PromptEntry(
                id: prompt.id,
                questions: prompt.questions,
                submittedSummary: Self.handledPromptSummary
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
