import Foundation
import OSLog

private let commitMessageGenerationLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Alveary",
    category: "CommitMessageGeneration"
)

extension ConversationViewModel {
    func generateCommitMessage(_ prompt: String) async throws -> String {
        try prepareHiddenCommitMessageGeneration()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                commitMessageGenerationContinuation = continuation
                Task { @MainActor [self] in
                    await runHiddenCommitMessageGenerationSend(prompt: prompt)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.failHiddenCommitMessageGeneration(.activeConversationChanged)
            }
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func shouldPersistHiddenCommitMessageGenerationEvent(_ event: ConversationEvent) -> Bool {
        switch event {
        case .sessionInit:
            return false
        case .permissionModeChanged(let permissionMode):
            syncRuntimePermissionMode(permissionMode)
            return false
        case .messageChunk(let text, let parentToolUseId):
            guard parentToolUseId == nil else {
                return false
            }
            state.clearStreamingText()
            state.hiddenCommitMessageResponse.append(text)
            return false
        case .message(let role, let content, _):
            if role == "assistant" {
                state.clearStreamingText()
                if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    state.hiddenCommitMessageResponse = content
                }
            }
            return false
        case .tokens:
            if let payload = TokenEventPayload(event) {
                handleHiddenCommitMessageGenerationTokens(payload)
            }
            return false
        case .runtimeActivity(let activityState, let turnId, let outcome):
            handleHiddenCommitMessageGenerationRuntimeActivity(
                state: activityState,
                turnId: turnId,
                outcome: outcome
            )
            return false
        case .toolApprovalRequested, .toolApprovalFailed:
            failHiddenCommitMessageGeneration(.approvalRequested)
            return false
        case .error(let message):
            failHiddenCommitMessageGeneration(.failed(message))
            return false
        default:
            return false
        }
    }

    func acknowledgeLateHiddenCommitMessageGenerationEvent(_ event: ConversationEvent) -> Bool {
        if case .permissionModeChanged(let permissionMode) = event {
            syncRuntimePermissionMode(permissionMode)
        }
        return false
    }
}

private extension ConversationViewModel {
    func prepareHiddenCommitMessageGeneration() throws {
        guard canStartHiddenCommitMessageGeneration else {
            throw CommitMessageGenerationError.busy
        }

        state.isGeneratingCommitMessage = true
        state.isDrainingCommitMessageGenerationEvents = false
        state.hiddenCommitMessageResponse = ""
        state.activeRuntimeActivityTurnId = nil
        state.clearStreamingText()
        state.lastTurnInterrupted = false
        state.isCancellingTurn = false
        state.lastTurnError = nil
        beginHiddenActivityTurn()
    }

    func runHiddenCommitMessageGenerationSend(prompt: String) async {
        do {
            try await setupHiddenInitialRuntimeIfNeeded()

            if await needsRespawn() {
                try await startAgentReserved(config: makeSpawnConfig(settingsSource: .currentContinuation))
                state.sessionContinuityNotice = nil
                state.respawnAttempts = 0
            }

            try await agentsManager.sendMessage(prompt, conversationId: conversation.id, activityVisibility: .hidden)
        } catch {
            failHiddenCommitMessageGeneration(.failed(error.localizedDescription))
        }
    }

    var canStartHiddenCommitMessageGeneration: Bool {
        initialSetupTask == nil &&
            setupPhase == nil &&
            !state.isCancellingInitialSetup &&
            !isAgentActivelyWorking &&
            !state.isSendingMessage &&
            !state.isReconfiguringSession &&
            !state.hasActiveSessionHandoff &&
            !state.isGeneratingCommitMessage &&
            state.pendingToolApproval == nil &&
            !hasUnansweredPrompt &&
            commitMessageGenerationContinuation == nil
    }

    func handleHiddenCommitMessageGenerationTokens(_ payload: TokenEventPayload) {
        state.clearStreamingText()
        guard payload.stopReason != ConversationEvent.interimUsageStopReason else {
            return
        }
        guard payload.completesTurn else {
            return
        }
        guard !payload.isError, payload.permissionDenials.isEmpty else {
            failHiddenCommitMessageGeneration(.failed(
                ConversationErrorDisplayPolicy.sessionHandoffTokenFailureMessage(stopReason: payload.stopReason)
            ))
            return
        }

        completeHiddenCommitMessageGeneration()
    }

    func handleHiddenCommitMessageGenerationRuntimeActivity(
        state activityState: ConversationRuntimeActivityState,
        turnId: String?,
        outcome: ConversationRuntimeActivityOutcome
    ) {
        switch activityState {
        case .active:
            state.activeRuntimeActivityTurnId = turnId
            state.turnState.beginTurn()
            scheduleSave()
        case .idle:
            handleHiddenCommitMessageGenerationRuntimeIdle(turnId: turnId, outcome: outcome)
        }
    }

    func handleHiddenCommitMessageGenerationRuntimeIdle(
        turnId: String?,
        outcome: ConversationRuntimeActivityOutcome
    ) {
        guard !shouldIgnoreRuntimeActivityIdle(turnId: turnId) else {
            scheduleSave()
            return
        }

        state.activeRuntimeActivityTurnId = nil
        state.clearStreamingText()
        switch outcome {
        case .unknown, .completed:
            completeHiddenCommitMessageGeneration()
        case .failed(let message):
            failHiddenCommitMessageGeneration(.failed(message))
        case .interrupted:
            failHiddenCommitMessageGeneration(.interrupted)
        }
    }

    func completeHiddenCommitMessageGeneration() {
        let output = state.hiddenCommitMessageResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            failHiddenCommitMessageGeneration(.emptyResponse)
            return
        }

        commitMessageGenerationLogger.debug("Hidden commit message completed length=\(output.count)")
        finishHiddenCommitMessageGeneration()
        commitMessageGenerationContinuation?.resume(returning: output)
        commitMessageGenerationContinuation = nil
    }

    func failHiddenCommitMessageGeneration(_ error: CommitMessageGenerationError) {
        commitMessageGenerationLogger.error("Hidden commit message failed: \(error.localizedDescription, privacy: .public)")
        finishHiddenCommitMessageGeneration()
        commitMessageGenerationContinuation?.resume(throwing: error)
        commitMessageGenerationContinuation = nil
    }

    func finishHiddenCommitMessageGeneration() {
        state.isGeneratingCommitMessage = false
        state.isDrainingCommitMessageGenerationEvents = true
        state.hiddenCommitMessageResponse = ""
        state.activeRuntimeActivityTurnId = nil
        state.clearStreamingText()
        state.isCancellingTurn = false
        state.endTurn()
        scheduleSave()
    }
}
