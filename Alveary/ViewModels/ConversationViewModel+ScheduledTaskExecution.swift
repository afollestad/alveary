import Foundation
import SwiftData

struct AutomatedScheduledUserStopRequest {
    let token: UUID
    let handler: @MainActor () async throws -> Void
}

extension ConversationViewModel {
    var isReadyForExistingScheduledTask: Bool {
        !isAgentActivelyWorking &&
            !state.isSendingMessage &&
            state.messageQueue.peekNext() == nil &&
            state.pendingToolApproval == nil &&
            !hasUnansweredPrompt &&
            !state.isReconfiguringSession &&
            !state.hasActiveSessionHandoff &&
            !state.isAutomaticSessionHandoffPending &&
            !state.isGeneratingCommitMessage &&
            !state.isAutomatedScheduledRunActive
    }

    var defersOrdinaryScheduledOutbound: Bool {
        if state.isAutomatedScheduledRunActive {
            return true
        }
        if dbThread()?.hasBlockingScheduledTaskRunAttachment == true {
            return true
        }
        if let threadKey = scheduledThreadRuntimeKey,
           runtimeStore.automatedScheduledRunID(threadKey: threadKey) != nil {
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
        let threadKey = scheduledThreadRuntimeKey
        automatedScheduledExecutionThreadKey = threadKey
        if let runID, let threadKey {
            runtimeStore.setAutomatedScheduledThreadActive(true, threadKey: threadKey, runID: runID)
        } else if let runID {
            runtimeStore.setAutomatedScheduledRunActive(true, runID: runID)
        }
        state.isAutomatedScheduledRunActive = true
    }

    func finishAutomatedScheduledRunExecution() {
        if let runID = automatedScheduledExecutionRunID {
            if let threadKey = automatedScheduledExecutionThreadKey {
                runtimeStore.setAutomatedScheduledThreadActive(false, threadKey: threadKey, runID: runID)
            } else {
                runtimeStore.setAutomatedScheduledRunActive(false, runID: runID)
            }
        }
        automatedScheduledExecutionRunID = nil
        automatedScheduledExecutionThreadKey = nil
        state.isAutomatedScheduledRunActive = false
        scheduleQueueDrainIfNeeded()
    }

    func reconcileScheduledTaskTerminalState() {
        guard !defersOrdinaryScheduledOutbound else {
            return
        }
        scheduleScheduledTerminalQueueDrainIfNeeded()
    }

    /// Starts the visible turn for a materialized scheduled Task or an attached existing task.
    func startAutomatedScheduledTurn(
        _ prompt: String,
        onRuntimePrepared: () throws -> Void = {}
    ) async throws {
        try validateAutomatedScheduledWorkspaceIfNeeded(isAutomatedScheduledTurn: true)
        let recoveryContext = try await prepareRuntimeForAutomatedScheduledTurn()
        try validateAutomatedScheduledWorkspaceIfNeeded(isAutomatedScheduledTurn: true)
        // Materialization persists the occurrence note before the background controller exists.
        // Hydrate that chronological boundary before live events advance the grouper's incremental cursor.
        rebuildChatItemsFromConversationRecords(forceFullRebuild: true)
        try onRuntimePrepared()

        let task = Task { @MainActor [self] in
            try await withOutboundReservation {
                try await deliverMessageReserved(
                    prompt,
                    stagedContextOverride: recoveryContext,
                    useCurrentStagedContextWhenOverrideNil: false,
                    respawnSettingsSource: .automatedScheduledRun,
                    isAutomatedScheduledTurn: true,
                    hostToolExposure: .currentContinuation
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

    private func prepareRuntimeForAutomatedScheduledTurn() async throws -> String? {
        guard !needsSetup,
              let runID = automatedScheduledExecutionRunID,
              dbThread()?.targetedScheduledTaskRuns.contains(where: {
                  $0.id == runID && $0.decodedDestinationSnapshot == .existingThread
              }) == true else {
            return nil
        }
        let config = try makeSpawnConfig(
            isAutomatedScheduledTurn: true,
            settingsSource: .automatedScheduledRun,
            hostToolExposure: .currentContinuation
        )
        await agentsManager.suspendRuntime(conversationId: conversation.id)
        try Task.checkCancellation()
        try validateAutomatedScheduledWorkspaceIfNeeded(isAutomatedScheduledTurn: true)
        let recoveryContext: String?
        do {
            try await startAgentReserved(config: config)
            recoveryContext = nil
        } catch {
            recoveryContext = try await recoverNonresumableSessionForOutboundIfNeeded(
                error,
                config: config
            )
        }
        state.runtimePermissionMode = config.permissionMode
        state.lastNonPlanPermissionMode = config.permissionMode
        state.runtimePlanModeEnabled = config.planModeEnabled
        state.runtimeSpeedMode = config.speedMode
        return recoveryContext
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
        if let runID = automatedScheduledExecutionRunID,
           let run = thread.targetedScheduledTaskRuns.first(where: { $0.id == runID }),
           run.decodedDestinationSnapshot == .existingThread {
            guard run.targetThread?.persistentModelID == thread.persistentModelID,
                  run.targetConversationIDSnapshot == conversation.id,
                  run.providerIDSnapshot == (dbConversation()?.provider ?? settingsService.current.defaultProvider),
                  run.modelSnapshot == thread.model,
                  run.effortSnapshot == thread.effort,
                  run.permissionModeSnapshot == thread.permissionMode,
                  run.planModeEnabledSnapshot == (thread.planModeEnabled ?? false),
                  run.speedModeSnapshot == thread.normalizedSpeedMode.rawValue else {
                throw AgentError.spawnFailed("The scheduled task target changed before execution")
            }
            try ScheduledTaskAutomatedWorkspaceValidator(
                workspaceOwnershipService: taskWorkspaceOwnershipService
            ).validateExistingTarget(thread: thread, run: run)
            return
        }
        try ScheduledTaskAutomatedWorkspaceValidator(
            workspaceOwnershipService: taskWorkspaceOwnershipService
        ).validate(thread: thread)
    }

    private var scheduledThreadRuntimeKey: String? {
        dbThread()?.conversations.first(where: \.isMain)?.id
    }

    @discardableResult
    func supersedeAutomatedScheduledPendingInteractions(
        interactionIDs allowedInteractionIDs: Set<String>? = nil
    ) -> Bool {
        let unresolvedApprovals = unresolvedScheduledApprovalRecords(
            allowedInteractionIDs: allowedInteractionIDs
        )
        let unresolvedPrompts = unresolvedScheduledPromptRecords(
            allowedInteractionIDs: allowedInteractionIDs
        )
        let pendingApprovalIsEligible = state.pendingToolApproval.map {
            allowedInteractionIDs?.contains($0.request.toolUseId) ?? true
        } ?? false
        let groupedPromptID = state.grouper.latestUnansweredPrompt?.id
        let latestUnansweredPromptID = groupedPromptID.flatMap { promptID in
            allowedInteractionIDs?.contains(promptID) == false ? nil : promptID
        }
        guard !unresolvedApprovals.isEmpty ||
            pendingApprovalIsEligible ||
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

        if pendingApprovalIsEligible {
            state.pendingToolApproval = nil
            clearPendingExitPlanModeDenialState()
        }
        refreshTranscriptForToolApprovalStatusChanges()
        scheduleSave()
        return true
    }

    private func unresolvedScheduledApprovalRecords(
        allowedInteractionIDs: Set<String>?
    ) -> [ConversationEventRecord] {
        let conversationID = conversation.id
        return ((try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == "tool_approval" &&
                        $0.toolApprovalStatus == nil
                }
            )
        )) ?? []).filter { record in
            allowedInteractionIDs?.contains(record.toolId ?? record.id) ?? true
        }
    }

    private func unresolvedScheduledPromptRecords(
        allowedInteractionIDs: Set<String>?
    ) -> [ConversationEventRecord] {
        let conversationID = conversation.id
        return ((try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == "tool_call" &&
                        $0.toolName == "AskUserQuestion"
                }
            )
        )) ?? []).filter { record in
            record.content?.isEmpty != false &&
                (allowedInteractionIDs?.contains(record.toolId ?? record.id) ?? true)
        }
    }
}
