import Foundation

extension ConversationViewModel {
    @discardableResult
    func reconfigureSession(config: AgentSpawnConfig) async throws -> AgentSessionReconfigureResult {
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

        await flushPendingSaveIfNeeded()
        await prepareForSpawn(config: config)
        let result = try await performRuntimeReconfigure(config: config)
        applyReconfigureResult(result, config: config)
        return result
    }

    @discardableResult
    func reconfigureSession() async throws -> AgentSessionReconfigureResult {
        try await reconfigureSession(config: makeSpawnConfig())
    }

    func resubscribeIfActiveRuntimeIsRunning() async {
        guard hasActivatedViewLifecycle,
              await agentsManager.isRunning(conversationId: conversation.id) else {
            return
        }
        subscribe()
    }

    private func performRuntimeReconfigure(config: AgentSpawnConfig) async throws -> AgentSessionReconfigureResult {
        do {
            return try await agentsManager.reconfigureSession(conversationId: conversation.id, config: config)
        } catch {
            await resubscribeIfActiveRuntimeIsRunning()
            throw error
        }
    }

    private func applyReconfigureResult(_ result: AgentSessionReconfigureResult, config: AgentSpawnConfig) {
        guard result == .restarted else {
            if result == .appliedInPlace {
                state.liveSessionConfig = config
                state.runtimeSpeedMode = config.speedMode
            }
            return
        }

        state.liveSessionConfig = config
        state.runtimeSpeedMode = config.speedMode
        state.lastObservedEventIndex = 0
        state.lastPersistedEventIndex = 0
        state.activeBufferGeneration = nil
        state.activeRuntimeActivityTurnId = nil
        state.grouper.resetInFlightStateForNewSession()
        subscribe()
    }
}
