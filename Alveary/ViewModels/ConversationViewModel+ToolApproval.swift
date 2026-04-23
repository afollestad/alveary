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

    func approveToolUseForSession(toolUseId: String, scope: ToolApprovalSessionScope) async throws {
        try await resolveToolUseApproval(
            toolUseId: toolUseId,
            decision: .allow,
            sessionApprovalScope: scope
        )
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
        state.turnState.endTurn()
        return true
    }

    func clearResolvedPendingToolApprovalIfNeeded() {
        guard let pendingApproval = state.pendingToolApproval,
              pendingApproval.status != .pending else {
            return
        }

        persistResolvedToolApproval(pendingApproval)
        state.pendingToolApproval = nil
    }

    func replacePendingToolApproval(with approval: ToolApprovalRequest) {
        if let pendingApproval = state.pendingToolApproval,
           let resolvedStatus = resolvedStatus(for: pendingApproval.status) {
            persistToolApprovalStatus(
                resolvedStatus,
                toolUseId: pendingApproval.request.toolUseId,
                sessionId: pendingApproval.request.sessionId,
                refreshTranscript: false
            )
        }

        supersedeUnresolvedToolApprovalRecords(refreshTranscript: false)
        refreshTranscriptForToolApprovalStatusChanges()
        state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
    }
}

private extension ConversationViewModel {
    func resolveToolUseApproval(
        toolUseId: String,
        decision: ClaudeToolApprovalDecision,
        sessionApprovalScope: ToolApprovalSessionScope? = nil
    ) async throws {
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

        pendingApproval.status = approvalStatus(
            for: decision,
            sessionApprovalScope: sessionApprovalScope
        )
        state.pendingToolApproval = pendingApproval
        state.isSendingMessage = true
        defer { state.isSendingMessage = false }

        do {
            try await resumeDeferredToolUse(
                pendingApproval,
                decision: decision,
                sessionApprovalScope: sessionApprovalScope
            )
        } catch {
            state.pendingToolApproval = PendingToolApproval(request: pendingApproval.request, status: .pending)
            state.lastTurnError = "Tool approval failed: \(error.localizedDescription)"
            throw error
        }
    }

    func resumeDeferredToolUse(
        _ pendingApproval: PendingToolApproval,
        decision: ClaudeToolApprovalDecision,
        sessionApprovalScope: ToolApprovalSessionScope?
    ) async throws {
        let config = try makeSpawnConfig()
        let sessionApproval = sessionApprovalScope.flatMap {
            pendingApproval.request.sessionApprovalGrant(
                conversationId: conversation.id,
                providerId: config.providerId,
                scope: $0
            )
        }
        await prepareForSpawn(config: config)
        await flushPendingSaveIfNeeded()
        resetSubscriptionTrackingForToolApprovalResume()
        let sessionApprovalEffective = try await agentsManager.resolveToolApproval(
            conversationId: conversation.id,
            approval: pendingApproval.request,
            decision: decision,
            sessionApproval: sessionApproval,
            config: config
        )
        if decision == .allow,
           sessionApprovalScope != nil,
           !sessionApprovalEffective {
            state.pendingToolApproval = PendingToolApproval(
                request: pendingApproval.request,
                status: .approving
            )
        }
        state.lastTurnError = nil
        subscribe()
    }

    func approvalStatus(
        for decision: ClaudeToolApprovalDecision,
        sessionApprovalScope: ToolApprovalSessionScope?
    ) -> ToolApprovalStatus {
        switch (decision, sessionApprovalScope) {
        case (.allow, .exact):
            return .approvingForSessionExact
        case (.allow, .group):
            return .approvingForSessionGroup
        case (.allow, nil):
            return .approving
        case (.deny, _):
            return .denying
        }
    }

    func resetSubscriptionTrackingForToolApprovalResume() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        state.lastObservedEventIndex = 0
        state.lastPersistedEventIndex = 0
        state.activeBufferGeneration = nil
        state.activeSubscriptionToken = nil
    }

    func persistResolvedToolApproval(_ pendingApproval: PendingToolApproval) {
        guard let resolvedStatus = resolvedStatus(for: pendingApproval.status) else {
            return
        }
        persistToolApprovalStatus(
            resolvedStatus,
            toolUseId: pendingApproval.request.toolUseId,
            sessionId: pendingApproval.request.sessionId
        )
    }

    func resolvedStatus(for status: ToolApprovalStatus) -> ToolApprovalStatus? {
        switch status {
        case .approving, .approved:
            return .approved
        case .approvingForSessionExact, .approvedForSessionExact:
            return .approvedForSessionExact
        case .approvingForSessionGroup, .approvedForSessionGroup:
            return .approvedForSessionGroup
        case .denying, .denied:
            return .denied
        case .pending, .superseded:
            return nil
        }
    }

    func supersedeUnresolvedToolApprovalRecords() {
        supersedeUnresolvedToolApprovalRecords(refreshTranscript: true)
    }

    func supersedeUnresolvedToolApprovalRecords(refreshTranscript: Bool) {
        let conversationID = conversation.id
        let unresolvedApprovalRecords = (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == "tool_approval" &&
                        $0.toolApprovalStatus == nil
                }
            )
        )) ?? []
        guard !unresolvedApprovalRecords.isEmpty else {
            return
        }

        for approvalRecord in unresolvedApprovalRecords {
            approvalRecord.toolApprovalStatus = ToolApprovalStatus.superseded.rawValue
        }
        do {
            try modelContext.save()
            if refreshTranscript {
                refreshTranscriptForToolApprovalStatusChanges()
            }
        } catch {
            // Best-effort: transcript history is still preserved even if superseded
            // rows stay unresolved until the next successful save.
        }
    }

    func persistToolApprovalStatus(
        _ status: ToolApprovalStatus,
        toolUseId: String,
        sessionId: String,
        refreshTranscript: Bool = true
    ) {
        let conversationID = conversation.id
        let approvalRecords = (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == "tool_approval" &&
                        $0.toolId == toolUseId &&
                        $0.content == sessionId
                },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        )) ?? []

        guard let approvalRecord = approvalRecords.first else {
            return
        }
        approvalRecord.toolApprovalStatus = status.rawValue
        do {
            try modelContext.save()
            if refreshTranscript {
                refreshTranscriptForToolApprovalStatusChanges()
            }
        } catch {
            // Best-effort: the live pending state already showed the chosen action.
        }
    }

    func refreshTranscriptForToolApprovalStatusChanges() {
        let conversationID = conversation.id
        let records = (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID
                },
                sortBy: [SortDescriptor(\.timestamp)]
            )
        )) ?? []
        rebuildChatItemsIfNeeded(from: records, forceFullRebuild: true)
    }

    func latestUnresolvedToolApproval() -> ToolApprovalRequest? {
        let conversationID = conversation.id
        guard let approvalRecord = latestToolApprovalRecord(conversationID: conversationID) else {
            return nil
        }

        let toolUseId = approvalRecord.toolId ?? approvalRecord.id
        guard approvalRecord.toolApprovalStatus == nil else {
            return nil
        }
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
