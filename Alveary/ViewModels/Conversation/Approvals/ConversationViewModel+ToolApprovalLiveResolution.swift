import Foundation
import SwiftData

struct ToolApprovalLiveResolutionResult {
    let additionalApprovals: [ToolApprovalRequest]
    let sessionApprovalEffective: Bool
}

extension ConversationViewModel {
    func resolveAgentToolApproval(
        _ pendingApproval: PendingToolApproval,
        resolution: ClaudeToolApprovalResolution,
        sessionApproval: AgentSessionApprovalGrant?,
        config: AgentSpawnConfig,
        requiresProviderRestart: Bool = false
    ) async throws -> ToolApprovalLiveResolutionResult {
        let additionalApprovals = relatedDeferredToolApprovals(for: pendingApproval.request)
        let sessionApprovalEffective = try await agentsManager.resolveToolApproval(
            AgentToolApprovalResolutionRequest(
                conversationId: conversation.id,
                approval: pendingApproval.request,
                resolution: resolution,
                additionalApprovals: additionalApprovals,
                sessionApproval: sessionApproval,
                config: config,
                requiresProviderRestart: requiresProviderRestart
            )
        )
        return ToolApprovalLiveResolutionResult(
            additionalApprovals: additionalApprovals,
            sessionApprovalEffective: sessionApprovalEffective
        )
    }

    /// Ends the local turn after a *live* denial, without waiting for the provider to confirm it.
    ///
    /// Claude should emit a terminal permission-denial result once the hook returns, but the UI must
    /// not stay locked in an active turn if that trailing token is delayed or dropped. Ending early
    /// is safe in the other direction too: later terminal tokens still process normally.
    ///
    /// Denial is the only decision that ends the turn here. A live *allow* continues the provider's
    /// turn, so `turnState` stays active until a real terminal event arrives.
    func finishLiveDeniedToolApprovalIfNeeded(
        isResolvingLiveHookApproval: Bool,
        decision: ClaudeToolApprovalDecision
    ) {
        guard isResolvingLiveHookApproval, decision == .deny else {
            return
        }

        state.completeDeferredControllerTurn()
        recordLocalVisibleTurnEndedIfNeeded()
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

    func clearApprovedExitPlanModeApprovalAfterImplementationToolCall(toolName: String) {
        guard toolName != "ExitPlanMode" else {
            return
        }
        clearApprovedExitPlanModeApprovalIfNeeded()
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
        let recordType = ConversationEventRecord.toolApprovalType
        let approvalRecords = (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == recordType &&
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

    /// Terminalizes any still-open approval rows for a tool whose result has now arrived.
    ///
    /// A completed tool result is proof the approval was answered, wherever that happened — another
    /// window, a previous launch, or the provider's own session state. Closing the rows stops restore
    /// from rehydrating them; `handleToolApprovalRequested` reads the same fact independently, so a
    /// late duplicate event is rejected whether or not this has run yet.
    func resolveUnresolvedToolApprovalsCompletedByToolResult(toolUseId: String) {
        let conversationID = conversation.id
        let recordType = ConversationEventRecord.toolApprovalType
        let approvalRecords = (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == recordType &&
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
                hydratePendingToolApprovalIfNeeded()
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
        let recordType = ConversationEventRecord.toolResultType
        return (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == recordType &&
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

    /// Stops an approved `ExitPlanMode` from blocking the composer, as soon as the stream proves the
    /// exit actually happened.
    ///
    /// Live hooks unblock Claude immediately, so implementation work can stream before the terminal
    /// token that normally finalizes a deferred approval. Waiting for that token would leave the
    /// composer blocked while the implementation is already arriving. Four things count as proof,
    /// all dispatched from `ConversationViewModel+EventHandling.swift`: a non-plan permission mode,
    /// collaboration mode reporting plan off, a successful matching tool result, or an
    /// implementation tool call that is not `ExitPlanMode`.
    ///
    /// Only an *approved* exit clears this way — a denial is terminal for the confirmation UI and is
    /// handled where the denial is taken.
    func clearApprovedExitPlanModeApprovalIfNeeded(toolUseId: String? = nil) {
        guard let pendingApproval = state.pendingToolApproval,
              pendingApproval.request.toolName == "ExitPlanMode",
              pendingApproval.status != .pending,
              resolvedStatus(for: pendingApproval.status) == .approved,
              toolUseId == nil || pendingApproval.request.toolUseId == toolUseId else {
            return
        }

        restorePermissionModeAfterPlanExitIfNeeded(pendingApproval)
        persistResolvedToolApproval(pendingApproval, refreshTranscript: false)
        state.pendingToolApproval = nil
        _ = enqueuePendingExitPlanModeFollowUpIfReady(clearedToolUseId: pendingApproval.request.toolUseId)
        refreshTranscriptForToolApprovalStatusChanges()
    }
}
