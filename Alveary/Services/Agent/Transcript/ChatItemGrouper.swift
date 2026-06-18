import AgentCLIKit
import Foundation
import Observation

@MainActor
@Observable
final class ChatItemGrouper {
    nonisolated static let handledPromptSummary = "Response already handled."

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
    var transcriptNoteToolKinds: [String: TranscriptNoteKind] = [:]
    var toolApprovalStatusesByToolId: [String: ToolApprovalStatus] = [:]
    var currentToolApprovalBatch: ToolApprovalBatchState?
    var pinnedPermissionApprovalItemIDs: Set<String> = []
    var markdownSnapshotsByPath: [String: MarkdownSnapshot] = [:]
    var exitPlanModePlanMarkdowns: [String] = []
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
        transcriptNoteToolKinds = [:]
        toolApprovalStatusesByToolId = [:]
        currentToolApprovalBatch = nil
        pinnedPermissionApprovalItemIDs = []
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

    func markPromptHandled(promptId: String) {
        markPromptAnswered(promptId: promptId, summary: Self.handledPromptSummary)
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

    var latestUnansweredPrompt: PromptEntry? {
        for item in items.reversed() {
            guard case .promptBlock(_, let prompt) = item,
                  prompt.submittedSummary == nil else {
                continue
            }
            return prompt
        }
        return nil
    }

    var hasUnansweredPrompt: Bool {
        latestUnansweredPrompt != nil
    }

    func appendLocalUserMessage(id: String, text: String) {
        flushGroup()
        flushSubAgents()
        appendTranscriptItem(.userMessage(id: id, text: text))
        processedCount += 1
    }

    func appendTranscriptItem(_ item: ChatItem) {
        releaseResolvedPinnedPermissionApprovalsIfNeeded(beforeAppending: item)

        if item.isPinnablePermissionApproval {
            items.append(item)
            updatePinnedPermissionApprovalTracking(for: item)
            return
        }

        guard let insertionIndex = transcriptPinnedTailInsertionIndex(for: item) else {
            items.append(item)
            return
        }

        items.insert(item, at: insertionIndex)
    }

    func replaceOrAppendTranscriptItem(_ item: ChatItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            appendTranscriptItem(item)
            return
        }

        items[index] = item
        updatePinnedPermissionApprovalTracking(for: item)
    }

    func updatePinnedPermissionApprovalTracking(for item: ChatItem) {
        if item.isPinnablePermissionApproval {
            pinnedPermissionApprovalItemIDs.insert(item.id)
        } else {
            pinnedPermissionApprovalItemIDs.remove(item.id)
        }
    }

    func unpinPermissionApprovalItem(id: String) {
        pinnedPermissionApprovalItemIDs.remove(id)
    }

    private func releaseResolvedPinnedPermissionApprovalsIfNeeded(beforeAppending item: ChatItem) {
        pruneMissingPinnedPermissionApprovals()

        guard item.opensPinnedPermissionApprovalBoundary else {
            return
        }

        let releasedIDs = Set(items.compactMap { existingItem -> String? in
            guard pinnedPermissionApprovalItemIDs.contains(existingItem.id),
                  existingItem.hasResolvedPermissionApprovalStatus else {
                return nil
            }
            return existingItem.id
        })
        guard !releasedIDs.isEmpty else {
            return
        }

        let releasedItems = items.filter { releasedIDs.contains($0.id) }
        items.removeAll { releasedIDs.contains($0.id) }
        pinnedPermissionApprovalItemIDs.subtract(releasedIDs)

        guard let insertionIndex = transcriptActivePinnedTailInsertionIndex() else {
            items.append(contentsOf: releasedItems)
            return
        }
        items.insert(contentsOf: releasedItems, at: insertionIndex)
    }

    private func transcriptPinnedTailInsertionIndex(for item: ChatItem) -> Array<ChatItem>.Index? {
        var candidates: [Array<ChatItem>.Index] = []
        if !item.isTaskListBlock,
           let latestTaskListIndex = items.lastIndex(where: \.isIncompleteTaskListBlock) {
            candidates.append(latestTaskListIndex)
        }
        if let firstApprovalIndex = items.firstIndex(where: { pinnedPermissionApprovalItemIDs.contains($0.id) }) {
            candidates.append(firstApprovalIndex)
        }
        return candidates.min()
    }

    private func transcriptActivePinnedTailInsertionIndex() -> Array<ChatItem>.Index? {
        var candidates: [Array<ChatItem>.Index] = []
        if let latestTaskListIndex = items.lastIndex(where: \.isIncompleteTaskListBlock) {
            candidates.append(latestTaskListIndex)
        }
        if let firstApprovalIndex = items.firstIndex(where: { pinnedPermissionApprovalItemIDs.contains($0.id) }) {
            candidates.append(firstApprovalIndex)
        }
        return candidates.min()
    }

    private func pruneMissingPinnedPermissionApprovals() {
        pinnedPermissionApprovalItemIDs.formIntersection(Set(items.map(\.id)))
    }
}

private extension ChatItem {
    var isTranscriptActivityItem: Bool {
        switch self {
        case .toolGroup(_, let tools):
            return !tools.isEmpty
        case .standaloneTool:
            return true
        case .subAgentBlock(_, let agents):
            return !agents.isEmpty
        case .promptBlock:
            return true
        case .userMessage,
             .assistantMessage,
             .taskListBlock,
             .toolApproval,
             .toolApprovalBatch,
             .transcriptNote,
             .error:
            return false
        }
    }

    var isPinnablePermissionApproval: Bool {
        switch self {
        case .toolApproval(_, let approval, _):
            return approval.isPinnablePermissionApproval
        case .toolApprovalBatch(_, let approvals, _):
            return !approvals.isEmpty && approvals.allSatisfy(\.isPinnablePermissionApproval)
        default:
            return false
        }
    }

    var hasResolvedPermissionApprovalStatus: Bool {
        switch self {
        case .toolApproval(_, _, let status),
             .toolApprovalBatch(_, _, let status):
            return status?.isResolvedPermissionApprovalStatus == true
        default:
            return false
        }
    }

    var opensPinnedPermissionApprovalBoundary: Bool {
        !isTranscriptActivityItem && !isPinnablePermissionApproval
    }
}

private extension ToolApprovalRequest {
    var isPinnablePermissionApproval: Bool {
        switch toolName {
        case "AskUserQuestion", "ExitPlanMode":
            return false
        default:
            return true
        }
    }
}

private extension ToolApprovalStatus {
    var isResolvedPermissionApprovalStatus: Bool {
        switch self {
        case .approved,
             .approvedForSessionExact,
             .approvedForSessionGroup,
             .denied,
             .superseded:
            return true
        case .pending,
             .approving,
             .denying,
             .approvingForSessionExact,
             .approvingForSessionGroup:
            return false
        }
    }
}
