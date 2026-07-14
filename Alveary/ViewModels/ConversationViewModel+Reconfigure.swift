import Foundation

struct ConversationRuntimeReconfigureOutcome {
    let result: AgentSessionReconfigureResult
    let hostToolTransition: SchedulingHostToolRuntimeTransition
}

extension ConversationViewModel {
    @discardableResult
    func reconfigureSession(config: AgentSpawnConfig) async throws -> AgentSessionReconfigureResult {
        try ensureOrdinaryScheduledOutboundAvailable()
        guard !isAgentActivelyWorking, !state.isSendingMessage else {
            throw AgentError.spawnFailed("Wait for the current turn/send to finish before applying session changes")
        }
        guard state.pendingToolApproval == nil else {
            throw AgentError.spawnFailed("Approve or deny the pending tool use before applying session changes")
        }
        guard !state.isReconfiguringSession else {
            return .nextTurnRequired
        }

        state.isReconfiguringSession = true
        defer { state.isReconfiguringSession = false }

        let hostToolTransition = state.beginSchedulingHostToolRuntimeTransition()
        do {
            await flushPendingSaveIfNeeded()
            try await prepareForSpawn(config: config)
            let outcome = try await performRuntimeReconfigure(
                config: config,
                hostToolTransition: hostToolTransition
            )
            applyReconfigureResult(outcome, config: config)
            return outcome.result
        } catch {
            state.finishSchedulingHostToolRuntimeTransition(
                hostToolTransition,
                appliedRequestedConfiguration: false
            )
            throw error
        }
    }

    @discardableResult
    func reconfigureSession() async throws -> AgentSessionReconfigureResult {
        try await reconfigureSession(config: makeSpawnConfig())
    }

    func resubscribeIfActiveRuntimeIsRunning() async {
        guard hasActivatedControllerLifecycle,
              await agentsManager.isRunning(conversationId: conversation.id) else {
            return
        }
        subscribe()
    }

    func performRuntimeReconfigure(
        config: AgentSpawnConfig,
        hostToolTransition: SchedulingHostToolRuntimeTransition
    ) async throws -> ConversationRuntimeReconfigureOutcome {
        do {
            let result = try await agentsManager.reconfigureSession(conversationId: conversation.id, config: config)
            return ConversationRuntimeReconfigureOutcome(
                result: result,
                hostToolTransition: hostToolTransition
            )
        } catch {
            await resubscribeIfActiveRuntimeIsRunning()
            throw error
        }
    }

    func applyReconfigureResult(_ outcome: ConversationRuntimeReconfigureOutcome, config: AgentSpawnConfig) {
        let result = outcome.result
        state.finishSchedulingHostToolRuntimeTransition(
            outcome.hostToolTransition,
            appliedRequestedConfiguration: result != .nextTurnRequired
        )
        guard result == .restarted else {
            if result == .appliedInPlace {
                state.liveSessionConfig = effectiveLiveSessionConfig(config)
                state.runtimeSpeedMode = config.speedMode
            }
            return
        }

        state.liveSessionConfig = effectiveLiveSessionConfig(config)
        state.runtimeSpeedMode = config.speedMode
        state.lastObservedEventIndex = 0
        state.lastPersistedEventIndex = 0
        state.activeBufferGeneration = nil
        state.activeRuntimeActivityTurnId = nil
        state.grouper.resetInFlightStateForNewSession()
        subscribe()
    }
}
