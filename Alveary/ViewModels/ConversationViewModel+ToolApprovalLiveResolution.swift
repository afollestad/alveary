import Foundation
import SwiftData

struct ToolApprovalLiveResolutionResult {
    let additionalApprovals: [ToolApprovalRequest]
    let sessionApprovalEffective: Bool
}

extension ConversationViewModel {
    func resolveAgentToolApproval(
        _ pendingApproval: PendingToolApproval,
        decision: ClaudeToolApprovalDecision,
        updatedToolInput: String?,
        sessionApproval: AgentSessionApprovalGrant?,
        config: AgentSpawnConfig
    ) async throws -> ToolApprovalLiveResolutionResult {
        let additionalApprovals = relatedDeferredToolApprovals(for: pendingApproval.request)
        let sessionApprovalEffective = try await agentsManager.resolveToolApproval(
            AgentToolApprovalResolutionRequest(
                conversationId: conversation.id,
                approval: pendingApproval.request,
                resolution: ClaudeToolApprovalResolution(
                    decision: decision,
                    updatedInput: updatedToolInput
                ),
                additionalApprovals: additionalApprovals,
                sessionApproval: sessionApproval,
                config: config
            )
        )
        return ToolApprovalLiveResolutionResult(
            additionalApprovals: additionalApprovals,
            sessionApprovalEffective: sessionApprovalEffective
        )
    }

    func finishLiveDeniedToolApprovalIfNeeded(
        isResolvingLiveHookApproval: Bool,
        decision: ClaudeToolApprovalDecision
    ) {
        guard isResolvingLiveHookApproval, decision == .deny else {
            return
        }

        // Claude should emit a terminal permission-denial result after the hook
        // returns, but the UI must not stay locked in an active turn if that
        // trailing token is delayed or dropped.
        state.turnState.endTurn()
        state.clearStreamingText()
        state.isAutomaticSessionHandoffPending = false
    }

    func clearApprovedExitPlanModeApprovalAfterPermissionModeChange(_ permissionMode: String) {
        guard permissionMode != "plan" else {
            return
        }
        clearApprovedExitPlanModeApprovalIfNeeded()
    }

    func clearApprovedExitPlanModeApprovalAfterToolResult(toolUseId: String, isError: Bool) {
        guard !isError else {
            return
        }
        clearApprovedExitPlanModeApprovalIfNeeded(toolUseId: toolUseId)
    }

    func persistResolvedToolApproval(_ pendingApproval: PendingToolApproval, refreshTranscript: Bool = true) {
        guard let resolvedStatus = resolvedStatus(for: pendingApproval.status) else {
            return
        }
        persistToolApprovalStatus(
            resolvedStatus,
            toolUseId: pendingApproval.request.toolUseId,
            sessionId: pendingApproval.request.sessionId,
            refreshTranscript: refreshTranscript
        )
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
                sortBy: [
                    SortDescriptor(\.timestamp, order: .reverse),
                    SortDescriptor(\.id, order: .reverse)
                ]
            )
        )) ?? []

        let unresolvedApprovalRecords = approvalRecords.filter { $0.toolApprovalStatus == nil }
        guard !unresolvedApprovalRecords.isEmpty else {
            return
        }
        for approvalRecord in unresolvedApprovalRecords {
            approvalRecord.toolApprovalStatus = status.rawValue
        }
        do {
            try modelContext.save()
            if refreshTranscript {
                refreshTranscriptForToolApprovalStatusChanges()
            }
        } catch {
            // Best-effort: the live pending state already showed the chosen action.
        }
    }

    func resolveUnresolvedToolApprovalsCompletedByToolResult(toolUseId: String) {
        let conversationID = conversation.id
        let approvalRecords = (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == "tool_approval" &&
                        $0.toolId == toolUseId &&
                        $0.toolApprovalStatus == nil
                }
            )
        )) ?? []
        guard !approvalRecords.isEmpty else {
            return
        }

        let status = completedToolResultApprovalStatus(toolUseId: toolUseId)
        for approvalRecord in approvalRecords {
            approvalRecord.toolApprovalStatus = status.rawValue
        }
        do {
            try modelContext.save()
            if state.pendingToolApproval?.request.toolUseId == toolUseId {
                state.pendingToolApproval = nil
                if enqueuePendingExitPlanModeFollowUpIfReady(clearedToolUseId: toolUseId),
                   !state.turnState.isActive {
                    handleTurnCompleted()
                }
            }
            refreshTranscriptForToolApprovalStatusChanges()
        } catch {
            // Best-effort: a completed tool row still prevents restore-time rehydration.
        }
    }

    func completedToolResultApprovalStatus(toolUseId: String) -> ToolApprovalStatus {
        guard let pendingApproval = state.pendingToolApproval,
              pendingApproval.request.toolUseId == toolUseId,
              let resolvedStatus = resolvedStatus(for: pendingApproval.status) else {
            return .approved
        }
        return resolvedStatus
    }

    func refreshTranscriptForToolApprovalStatusChanges() {
        let conversationID = conversation.id
        let records = (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID
                },
                sortBy: [
                    SortDescriptor(\.timestamp),
                    SortDescriptor(\.id)
                ]
            )
        )) ?? []
        rebuildChatItemsIfNeeded(from: records, forceFullRebuild: true)
    }

    func toolApprovalAlreadyHasResult(_ approval: ToolApprovalRequest) -> Bool {
        let conversationID = conversation.id
        let toolUseId = approval.toolUseId
        return (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == "tool_result" &&
                        $0.toolId == toolUseId
                }
            )
        ).isEmpty == false) ?? false
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

    func restorePermissionModeAfterPlanExitIfNeeded(_ pendingApproval: PendingToolApproval) {
        guard pendingApproval.request.toolName == "ExitPlanMode",
              pendingApproval.status != .denying,
              pendingApproval.status != .denied,
              effectivePlanModeEnabled else {
            return
        }

        syncRuntimePlanMode(false)
        syncRuntimePermissionMode(state.lastNonPlanPermissionMode ?? "default")
    }

    func clearApprovedExitPlanModeApprovalIfNeeded(toolUseId: String? = nil) {
        guard let pendingApproval = state.pendingToolApproval,
              pendingApproval.request.toolName == "ExitPlanMode",
              pendingApproval.status != .pending,
              resolvedStatus(for: pendingApproval.status) == .approved,
              toolUseId == nil || pendingApproval.request.toolUseId == toolUseId else {
            return
        }

        // Live hooks unblock Claude immediately, so implementation work can stream
        // before the terminal token that normally finalizes a deferred approval.
        // Clear plan-exit approval as soon as the stream proves the exit happened.
        restorePermissionModeAfterPlanExitIfNeeded(pendingApproval)
        persistResolvedToolApproval(pendingApproval, refreshTranscript: false)
        state.pendingToolApproval = nil
        _ = enqueuePendingExitPlanModeFollowUpIfReady(clearedToolUseId: pendingApproval.request.toolUseId)
        refreshTranscriptForToolApprovalStatusChanges()
    }
}
