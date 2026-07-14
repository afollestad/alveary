import Foundation
import SwiftData

struct AutomatedScheduledUserStopRequest {
    let token: UUID
    let handler: @MainActor () async throws -> Void
}

extension ConversationViewModel {
    var defersOrdinaryScheduledOutbound: Bool {
        if state.isAutomatedScheduledRunActive {
            return true
        }
        guard let run = dbThread()?.scheduledTaskRun else {
            return false
        }
        if runtimeStore.isAutomatedScheduledRunActive(runID: run.id) {
            return true
        }
        return !run.hasKnownTerminalStatus
    }

    func beginAutomatedScheduledRunExecution(runID: String? = nil) {
        let runID = runID ?? dbThread()?.scheduledTaskRun?.id
        automatedScheduledExecutionRunID = runID
        if let runID {
            runtimeStore.setAutomatedScheduledRunActive(true, runID: runID)
        }
        state.isAutomatedScheduledRunActive = true
    }

    func finishAutomatedScheduledRunExecution() {
        if let runID = automatedScheduledExecutionRunID {
            runtimeStore.setAutomatedScheduledRunActive(false, runID: runID)
        }
        automatedScheduledExecutionRunID = nil
        state.isAutomatedScheduledRunActive = false
        scheduleQueueDrainIfNeeded()
    }

    func reconcileScheduledTaskTerminalState() {
        guard !defersOrdinaryScheduledOutbound else {
            return
        }
        scheduleScheduledTerminalQueueDrainIfNeeded()
    }

    /// Starts the first visible turn for a materialized scheduled Task. Follow-up turns use the
    /// ordinary outbound path so the provider is relaunched without automated-turn restrictions.
    func startAutomatedScheduledTurn(_ prompt: String) async throws {
        guard needsSetup else {
            throw AgentError.spawnFailed("The scheduled task conversation has already been started")
        }
        try validateAutomatedScheduledWorkspaceIfNeeded(isAutomatedScheduledTurn: true)
        // Materialization persists the occurrence note before the background controller exists.
        // Hydrate that prefix before live events advance the grouper's incremental cursor.
        rebuildChatItemsIfNeeded(from: conversationEventRecords(), forceFullRebuild: true)

        let task = Task { @MainActor [self] in
            try await withOutboundReservation {
                try await deliverMessageReserved(
                    prompt,
                    useCurrentStagedContextWhenOverrideNil: false,
                    isAutomatedScheduledTurn: true
                )
            }
        }
        initialSetupTask = task
        defer { initialSetupTask = nil }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func installAutomatedScheduledUserStopHandler(
        _ handler: (@MainActor () async throws -> Void)?
    ) -> UUID? {
        guard let handler else {
            return nil
        }
        precondition(automatedScheduledUserStopRequest == nil, "A scheduled user-stop handler is already installed")
        let token = UUID()
        automatedScheduledUserStopRequest = AutomatedScheduledUserStopRequest(token: token, handler: handler)
        return token
    }

    func removeAutomatedScheduledUserStopHandler(token: UUID?) {
        guard automatedScheduledUserStopRequest?.token == token else {
            return
        }
        automatedScheduledUserStopRequest = nil
    }

    func takeAutomatedScheduledUserStopRequest() -> AutomatedScheduledUserStopRequest? {
        defer { automatedScheduledUserStopRequest = nil }
        return automatedScheduledUserStopRequest
    }

    /// A fallback `tool_deferred` stop has already ended the local turn, so ordinary cancellation
    /// intentionally ignores it. Scheduled execution owns a stronger stop boundary: discard the
    /// waiting runtime and close the deferred controller turn.
    func interruptInactiveAutomatedScheduledDeferredInteractionIfNeeded() async -> Bool {
        guard state.isAutomatedScheduledRunActive,
              state.hasDeferredControllerTerminalBoundary,
              !state.turnState.isActive else {
            return false
        }

        await agentsManager.discardInactiveDeferredInteractionRuntime(conversationId: conversation.id)
        state.clearStreamingText()
        interruptRuntimeActivityForAutomatedScheduledStop()
        recordLocalVisibleTurnEndedIfNeeded()
        return true
    }

    func validateAutomatedScheduledWorkspaceIfNeeded(isAutomatedScheduledTurn: Bool) throws {
        guard isAutomatedScheduledTurn else {
            return
        }
        guard let thread = dbThread() else {
            throw AgentError.spawnFailed("The scheduled task conversation no longer has a task")
        }
        try ScheduledTaskAutomatedWorkspaceValidator(
            workspaceOwnershipService: taskWorkspaceOwnershipService
        ).validate(thread: thread)
    }

    @discardableResult
    func supersedeAutomatedScheduledPendingInteractions() -> Bool {
        let conversationID = conversation.id
        let unresolvedApprovals = (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == "tool_approval" &&
                        $0.toolApprovalStatus == nil
                }
            )
        )) ?? []
        let unresolvedPrompts = ((try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == "tool_call" &&
                        $0.toolName == "AskUserQuestion"
                }
            )
        )) ?? []).filter { $0.content?.isEmpty != false }
        let latestUnansweredPromptID = state.grouper.latestUnansweredPrompt?.id
        guard !unresolvedApprovals.isEmpty ||
            state.pendingToolApproval != nil ||
            !unresolvedPrompts.isEmpty ||
            latestUnansweredPromptID != nil else {
            return false
        }
        for approval in unresolvedApprovals {
            approval.toolApprovalStatus = ToolApprovalStatus.superseded.rawValue
        }
        for prompt in unresolvedPrompts {
            prompt.content = ChatItemGrouper.handledPromptSummary
            state.grouper.markPromptHandled(promptId: prompt.toolId ?? prompt.id)
        }
        if let latestUnansweredPromptID,
           !unresolvedPrompts.contains(where: { ($0.toolId ?? $0.id) == latestUnansweredPromptID }) {
            recordPromptHandled(promptId: latestUnansweredPromptID)
        }

        state.pendingToolApproval = nil
        clearPendingExitPlanModeDenialState()
        refreshTranscriptForToolApprovalStatusChanges()
        scheduleSave()
        return true
    }
}
