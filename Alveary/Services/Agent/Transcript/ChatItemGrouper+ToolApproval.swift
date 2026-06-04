import Foundation

extension ChatItemGrouper {
    func appendToolApproval(_ approval: ToolApprovalRequest, status: ToolApprovalStatus?) {
        let approval = approvalWithFallbackPlanIfNeeded(approval)

        if updateExistingRenderedApproval(approval, status: status) {
            return
        }

        guard let currentToolApprovalBatch,
              currentToolApprovalBatch.sessionId == approval.sessionId,
              currentToolApprovalBatch.status == status,
              let index = items.firstIndex(where: { $0.id == currentToolApprovalBatch.itemId }),
              ClaudeApprovalDisplayPolicy.canBatchPotentialApprovalToolCall(
                  toolName: approval.toolName,
                  with: approvalToolNames(in: items[index])
              ) else {
            appendSingleToolApproval(approval, status: status)
            return
        }

        let item = items.remove(at: index)
        let approvals: [ToolApprovalRequest]
        let itemId: String
        switch item {
        case .toolApproval(_, let existingApproval, _):
            itemId = "approval-batch-\(existingApproval.toolUseId)"
            approvals = [existingApproval, approval]
        case .toolApprovalBatch(let id, let existingApprovals, _):
            itemId = id
            approvals = existingApprovals.contains(where: { $0.toolUseId == approval.toolUseId })
                ? existingApprovals
                : existingApprovals + [approval]
        default:
            appendSingleToolApproval(approval, status: status)
            return
        }

        appendTranscriptItem(.toolApprovalBatch(id: itemId, approvals: approvals, status: status))
        self.currentToolApprovalBatch = ToolApprovalBatchState(
            itemId: itemId,
            sessionId: approval.sessionId,
            status: status
        )
    }

    private func approvalWithFallbackPlanIfNeeded(_ approval: ToolApprovalRequest) -> ToolApprovalRequest {
        guard approval.toolName == "ExitPlanMode",
              approval.planMarkdown == nil,
              let planItemIndex = fallbackPlanItemIndexForExitPlanModeApproval(),
              let fallbackPlanMarkdown = fallbackPlanMarkdown(from: items[planItemIndex]) else {
            return approval
        }

        // Some Claude `ExitPlanMode` hook payloads arrive with `{}` input even though
        // the assistant just wrote the plan. Treat that recent message as
        // approval-local plan display without mutating the tool input sent to Claude.
        items.remove(at: planItemIndex)
        return approval.withPlanMarkdownFallback(fallbackPlanMarkdown)
    }

    private func fallbackPlanItemIndexForExitPlanModeApproval() -> Array<ChatItem>.Index? {
        var index = items.endIndex
        while index > items.startIndex {
            index = items.index(before: index)
            let item = items[index]
            if case .assistantMessage = item {
                return index
            }
            guard canSkipForExitPlanModeFallbackPlanSearch(item) else {
                return nil
            }
        }
        return nil
    }

    private func fallbackPlanMarkdown(from item: ChatItem) -> String? {
        guard case .assistantMessage(_, let text) = item else {
            return nil
        }
        return text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private func canSkipForExitPlanModeFallbackPlanSearch(_ item: ChatItem) -> Bool {
        guard case .toolGroup(_, let tools) = item else {
            return false
        }
        return !tools.isEmpty && tools.allSatisfy(isExitPlanModeToolSearch)
    }

    private func isExitPlanModeToolSearch(_ tool: ToolEntry) -> Bool {
        guard tool.name == "ToolSearch",
              let data = tool.input.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = object["query"] as? String,
              query.hasPrefix("select:") else {
            return false
        }

        return query
            .dropFirst("select:".count)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains("ExitPlanMode")
    }

    private func appendSingleToolApproval(_ approval: ToolApprovalRequest, status: ToolApprovalStatus?) {
        let itemId = "approval-\(approval.toolUseId)"
        appendTranscriptItem(
            .toolApproval(
                id: itemId,
                approval: approval,
                status: status
            )
        )
        self.currentToolApprovalBatch = ToolApprovalBatchState(
            itemId: itemId,
            sessionId: approval.sessionId,
            status: status
        )
    }

    func appendStandaloneToolToCurrentApprovalBatchIfNeeded(_ tool: ToolEntry) -> Bool {
        // Parallel tool_use rows can arrive before their PreToolUse hooks; keep those rows in the
        // same approval batch so one eventual prompt honestly represents every held tool.
        guard let currentToolApprovalBatch,
              let index = items.firstIndex(where: { $0.id == currentToolApprovalBatch.itemId }),
              ClaudeApprovalDisplayPolicy.canBatchPotentialApprovalToolCall(
                  toolName: tool.name,
                  with: approvalToolNames(in: items[index])
              ) else {
            return false
        }

        let approval = ToolApprovalRequest(
            sessionId: currentToolApprovalBatch.sessionId,
            toolUseId: tool.id,
            toolName: tool.name,
            toolInput: tool.input
        )

        let approvalItem = items.remove(at: index)
        appendTranscriptItem(.standaloneTool(id: "tool-\(tool.id)", tool: tool))
        return appendApproval(
            approval,
            status: currentToolApprovalBatch.status,
            toApprovalItem: approvalItem
        )
    }

    func clearCurrentToolApprovalBatchIfResultCompletes(toolId: String) {
        guard let currentToolApprovalBatch else {
            return
        }
        guard let index = items.firstIndex(where: { $0.id == currentToolApprovalBatch.itemId }) else {
            self.currentToolApprovalBatch = nil
            return
        }
        guard approvalToolIds(in: items[index]).contains(toolId) else {
            return
        }
        self.currentToolApprovalBatch = nil
    }

    private func approvalToolNames(in item: ChatItem) -> [String] {
        switch item {
        case .toolApproval(_, let approval, _):
            return [approval.toolName]
        case .toolApprovalBatch(_, let approvals, _):
            return approvals.map(\.toolName)
        default:
            return []
        }
    }

    private func updateExistingRenderedApproval(_ approval: ToolApprovalRequest, status: ToolApprovalStatus?) -> Bool {
        for index in items.indices {
            switch items[index] {
            case .toolApproval(let id, let existingApproval, let existingStatus)
                where existingApproval.toolUseId == approval.toolUseId:
                items[index] = .toolApproval(
                    id: id,
                    approval: approvalByPreservingPlanFallbackIfNeeded(approval, from: existingApproval),
                    status: existingStatus ?? status
                )
                return true
            case .toolApprovalBatch(let id, let approvals, let existingStatus)
                where approvals.contains(where: { $0.toolUseId == approval.toolUseId }):
                let updatedApprovals = approvals.map { existingApproval in
                    existingApproval.toolUseId == approval.toolUseId
                        ? approvalByPreservingPlanFallbackIfNeeded(approval, from: existingApproval)
                        : existingApproval
                }
                items[index] = .toolApprovalBatch(
                    id: id,
                    approvals: updatedApprovals,
                    status: existingStatus ?? status
                )
                return true
            default:
                continue
            }
        }
        return false
    }

    private func approvalByPreservingPlanFallbackIfNeeded(
        _ approval: ToolApprovalRequest,
        from existingApproval: ToolApprovalRequest
    ) -> ToolApprovalRequest {
        guard approval.planMarkdown == nil,
              let existingPlanMarkdown = existingApproval.planMarkdown else {
            return approval
        }
        return approval.withPlanMarkdownFallback(existingPlanMarkdown)
    }

    private func approvalToolIds(in item: ChatItem) -> Set<String> {
        switch item {
        case .toolApproval(_, let approval, _):
            return [approval.toolUseId]
        case .toolApprovalBatch(_, let approvals, _):
            return Set(approvals.map(\.toolUseId))
        default:
            return []
        }
    }

    private func appendApproval(
        _ approval: ToolApprovalRequest,
        status: ToolApprovalStatus?,
        toApprovalItem item: ChatItem
    ) -> Bool {
        let itemId: String
        let approvals: [ToolApprovalRequest]
        switch item {
        case .toolApproval(_, let existingApproval, _):
            itemId = "approval-batch-\(existingApproval.toolUseId)"
            approvals = [existingApproval, approval]
        case .toolApprovalBatch(let id, let existingApprovals, _):
            itemId = id
            approvals = existingApprovals.contains(where: { $0.toolUseId == approval.toolUseId })
                ? existingApprovals
                : existingApprovals + [approval]
        default:
            return false
        }

        appendTranscriptItem(.toolApprovalBatch(id: itemId, approvals: approvals, status: status))
        self.currentToolApprovalBatch = ToolApprovalBatchState(
            itemId: itemId,
            sessionId: approval.sessionId,
            status: status
        )
        return true
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
