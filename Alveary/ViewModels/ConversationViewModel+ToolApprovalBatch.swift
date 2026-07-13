import AgentCLIKit
import Foundation

extension ConversationViewModel {
    func relatedDeferredToolApprovals(for approval: ToolApprovalRequest) -> [ToolApprovalRequest] {
        guard let dbConversation = dbConversation() else {
            return []
        }
        guard ClaudeApprovalDisplayPolicy.canRenderToolApproval(approval.toolName) else {
            return []
        }

        let orderedEvents = orderedApprovalBatchEvents(in: dbConversation)
        guard let approvalIndex = approvalEventIndex(for: approval, in: orderedEvents) else {
            return []
        }

        let bounds = approvalBatchBounds(containing: approvalIndex, in: orderedEvents)
        let completedToolIds = toolResultIds(in: orderedEvents[bounds.lowerBound..<bounds.upperBound])
        let approvalToolIds = approvalIds(
            sessionId: approval.sessionId,
            in: orderedEvents[bounds.lowerBound..<bounds.upperBound]
        )
        var relatedApprovals = relatedApprovalRows(
            for: approval,
            in: orderedEvents[bounds.lowerBound..<bounds.upperBound],
            completedToolIds: completedToolIds
        )
        relatedApprovals.append(contentsOf: relatedApprovalToolCalls(
            for: approval,
            in: orderedEvents[bounds.lowerBound..<bounds.upperBound],
            context: ApprovalBatchToolCallContext(
                completedToolIds: completedToolIds,
                approvalToolIds: approvalToolIds,
                existingRelatedToolIds: Set(relatedApprovals.map(\.toolUseId)),
                approvalToolNames: [approval.toolName] + relatedApprovals.map(\.toolName),
                workingDirectory: approvalBatchWorkingDirectory()
            )
        ))
        return relatedApprovals
    }
}

private struct ApprovalBatchToolCallContext {
    let completedToolIds: Set<String>
    let approvalToolIds: Set<String>
    let existingRelatedToolIds: Set<String>
    let approvalToolNames: [String]
    let workingDirectory: URL?
}

private extension ConversationViewModel {
    func orderedApprovalBatchEvents(in conversation: Conversation) -> [ConversationEventRecord] {
        conversation.events.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id < rhs.id
            }
            return lhs.timestamp < rhs.timestamp
        }
    }

    func approvalEventIndex(
        for approval: ToolApprovalRequest,
        in orderedEvents: [ConversationEventRecord]
    ) -> Array<ConversationEventRecord>.Index? {
        orderedEvents.lastIndex {
            $0.type == "tool_approval" &&
                $0.content == approval.sessionId &&
                $0.toolId == approval.toolUseId
        }
    }

    func approvalBatchBounds(
        containing approvalIndex: Array<ConversationEventRecord>.Index,
        in orderedEvents: [ConversationEventRecord]
    ) -> Range<Array<ConversationEventRecord>.Index> {
        // A live approval batch is bounded by transcript-break events, not by approval rows:
        // Claude may emit several sibling tool calls first and then invoke their hooks one at a time.
        // Keep tool results inside the window so unrelated read-only completions do not split
        // parallel approval hooks; `completedToolIds` below excludes any tool whose own result arrived.
        let lowerBound = orderedEvents[..<approvalIndex].lastIndex(where: isApprovalBatchBoundary)
            .map { orderedEvents.index(after: $0) } ?? orderedEvents.startIndex
        let upperBound = orderedEvents[orderedEvents.index(after: approvalIndex)...].firstIndex {
            isApprovalBatchBoundary($0)
        } ?? orderedEvents.endIndex
        return lowerBound..<upperBound
    }

    func isApprovalBatchBoundary(_ record: ConversationEventRecord) -> Bool {
        switch record.type {
        case "message", "error", "stop":
            return true
        default:
            return false
        }
    }

    func toolResultIds(
        in records: ArraySlice<ConversationEventRecord>
    ) -> Set<String> {
        Set(records.compactMap { record -> String? in
            record.type == "tool_result" ? record.toolId : nil
        })
    }

    func approvalIds(
        sessionId: String,
        in records: ArraySlice<ConversationEventRecord>
    ) -> Set<String> {
        Set(records.compactMap { record -> String? in
            guard record.type == "tool_approval",
                  record.content == sessionId else {
                return nil
            }
            return record.toolId
        })
    }

    func relatedApprovalRows(
        for approval: ToolApprovalRequest,
        in records: ArraySlice<ConversationEventRecord>,
        completedToolIds: Set<String>
    ) -> [ToolApprovalRequest] {
        records.compactMap { record -> ToolApprovalRequest? in
            guard record.type == "tool_approval",
                  record.content == approval.sessionId,
                  let toolUseId = record.toolId,
                  toolUseId != approval.toolUseId,
                  !completedToolIds.contains(toolUseId),
                  record.toolApprovalStatus == nil,
                  let toolName = record.toolName,
                  ClaudeApprovalDisplayPolicy.canRenderToolApproval(toolName),
                  ClaudeApprovalDisplayPolicy.canBatchPotentialApprovalToolCall(
                      toolName: toolName,
                      with: [approval.toolName]
                  ),
                  let toolInput = record.toolInput else {
                return nil
            }
            return ToolApprovalRequest(
                sessionId: approval.sessionId,
                toolUseId: toolUseId,
                toolName: toolName,
                toolInput: toolInput
            )
        }
    }

    func relatedApprovalToolCalls(
        for approval: ToolApprovalRequest,
        in records: ArraySlice<ConversationEventRecord>,
        context: ApprovalBatchToolCallContext
    ) -> [ToolApprovalRequest] {
        records.compactMap { record -> ToolApprovalRequest? in
            guard record.type == "tool_call",
                  let toolUseId = record.toolId,
                  toolUseId != approval.toolUseId,
                  !context.completedToolIds.contains(toolUseId),
                  !context.approvalToolIds.contains(toolUseId),
                  !context.existingRelatedToolIds.contains(toolUseId),
                  let toolName = record.toolName,
                  let toolInput = record.toolInput,
                  shouldBatchToolCallApproval(
                      toolName: toolName,
                      toolInput: toolInput,
                      with: context.approvalToolNames,
                      workingDirectory: context.workingDirectory
                  ) else {
                return nil
            }
            return ToolApprovalRequest(
                sessionId: approval.sessionId,
                toolUseId: toolUseId,
                toolName: toolName,
                toolInput: toolInput
            )
        }
    }

    func shouldBatchToolCallApproval(
        toolName: String,
        toolInput: String,
        with approvalToolNames: [String],
        workingDirectory: URL?
    ) -> Bool {
        guard let toolInput = agentCLIKitJSONValueForBatching(from: toolInput) else {
            return false
        }
        return ClaudeApprovalDisplayPolicy.shouldBatchDeferredToolCall(
            toolName: toolName,
            toolInput: toolInput,
            with: approvalToolNames,
            permissionMode: effectivePlanModeEnabled ? "plan" : effectivePermissionMode,
            workingDirectory: workingDirectory
        )
    }

    func approvalBatchWorkingDirectory() -> URL? {
        let workingDirectory = state.pendingSessionSettingsChange?.liveSessionConfig?.workingDirectory
            ?? state.liveSessionConfig?.workingDirectory
            ?? dbConversation()?.thread?.primaryWorkingDirectory
        guard let workingDirectory, !workingDirectory.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: workingDirectory, isDirectory: true)
    }

    func agentCLIKitJSONValueForBatching(from string: String) -> AgentCLIKit.JSONValue? {
        guard let data = string.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(AgentCLIKit.JSONValue.self, from: data)
    }
}
