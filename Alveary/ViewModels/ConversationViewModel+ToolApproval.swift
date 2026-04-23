import Foundation
import SwiftData

extension ConversationViewModel {
    func hydratePendingToolApprovalIfNeeded() {
        guard state.pendingToolApproval == nil,
              let approval = latestUnresolvedToolApproval() else {
            return
        }

        state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
    }

    func approveToolUse(toolUseId: String) async throws {
        try await resolveToolUseApproval(toolUseId: toolUseId, decision: .allow)
    }

    func denyToolUse(toolUseId: String) async throws {
        try await resolveToolUseApproval(toolUseId: toolUseId, decision: .deny)
    }
}

extension ConversationViewModel {
    func handleToolDeferredTokenIfNeeded(_ payload: TokenEventPayload) -> Bool {
        guard payload.stopReason == "tool_deferred" else {
            return false
        }

        state.isCancellingTurn = false
        state.lastTurnInterrupted = false
        state.lastTurnError = nil
        state.lastPermissionDeniedToolNames = []
        state.showPermissionBanner = false
        state.turnState.endTurn()
        return true
    }

    func clearResolvedPendingToolApprovalIfNeeded() {
        guard let pendingApproval = state.pendingToolApproval,
              pendingApproval.status != .pending else {
            return
        }

        state.pendingToolApproval = nil
    }
}

private extension ConversationViewModel {
    func resolveToolUseApproval(toolUseId: String, decision: ClaudeToolApprovalDecision) async throws {
        guard var pendingApproval = state.pendingToolApproval,
              pendingApproval.request.toolUseId == toolUseId else {
            return
        }
        guard pendingApproval.status == .pending else {
            return
        }
        guard !state.turnState.isActive, !state.isSendingMessage else {
            throw AgentError.spawnFailed("Wait for the current turn to finish before resolving tool approval")
        }

        pendingApproval.status = decision == .allow ? .approving : .denying
        state.pendingToolApproval = pendingApproval
        state.isSendingMessage = true
        defer { state.isSendingMessage = false }

        do {
            try await resumeDeferredToolUse(pendingApproval, decision: decision)
        } catch {
            state.pendingToolApproval = PendingToolApproval(request: pendingApproval.request, status: .pending)
            state.lastTurnError = "Tool approval failed: \(error.localizedDescription)"
            throw error
        }
    }

    func resumeDeferredToolUse(
        _ pendingApproval: PendingToolApproval,
        decision: ClaudeToolApprovalDecision
    ) async throws {
        let config = try makeSpawnConfig()
        await prepareForSpawn(config: config)
        await flushPendingSaveIfNeeded()
        resetSubscriptionTrackingForToolApprovalResume()
        try await agentsManager.resolveToolApproval(
            conversationId: conversation.id,
            approval: pendingApproval.request,
            decision: decision,
            config: config
        )
        state.lastTurnError = nil
        subscribe()
    }

    func resetSubscriptionTrackingForToolApprovalResume() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        state.lastObservedEventIndex = 0
        state.lastPersistedEventIndex = 0
        state.activeBufferGeneration = nil
        state.activeSubscriptionToken = nil
    }

    func latestUnresolvedToolApproval() -> ToolApprovalRequest? {
        let conversationID = conversation.id
        guard let approvalRecord = latestToolApprovalRecord(conversationID: conversationID) else {
            return nil
        }

        let toolUseId = approvalRecord.toolId ?? approvalRecord.id
        guard !hasResolutionAfterApproval(conversationID: conversationID, toolUseId: toolUseId, approvalRecord: approvalRecord) else {
            return nil
        }

        return ToolApprovalRequest(
            sessionId: approvalRecord.content ?? "",
            toolUseId: toolUseId,
            toolName: approvalRecord.toolName ?? "Tool",
            toolInput: approvalRecord.toolInput ?? "{}"
        )
    }

    func latestToolApprovalRecord(conversationID: String) -> ConversationEventRecord? {
        try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == "tool_approval"
                },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        ).first
    }

    func hasResolutionAfterApproval(
        conversationID: String,
        toolUseId: String,
        approvalRecord: ConversationEventRecord
    ) -> Bool {
        let approvalTimestamp = approvalRecord.timestamp
        let hasToolResult = (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == "tool_result" &&
                        $0.toolId == toolUseId &&
                        $0.timestamp > approvalTimestamp
                }
            )
        ).isEmpty == false) ?? false
        if hasToolResult {
            return true
        }

        let laterTokens = (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == "tokens" &&
                        $0.timestamp > approvalTimestamp
                }
            )
        )) ?? []
        return laterTokens.contains { token in
            guard let stopReason = token.stopReason else {
                return false
            }
            return stopReason != "tool_deferred"
        }
    }
}
