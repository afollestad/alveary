import AgentCLIKit
import Foundation

extension DefaultAgentsManager {
    func sendMessage(
        _ message: String,
        conversationId: String,
        activityVisibility: AgentTurnActivityVisibility
    ) async throws {
        try await sendMessageWithAgentCLIKit(
            message,
            conversationId: conversationId,
            activityVisibility: activityVisibility
        )
    }

    func sendGoalStartMessage(
        _ message: String,
        initialGoal: String,
        conversationId: String,
        activityVisibility: AgentTurnActivityVisibility
    ) async throws {
        try await sendGoalStartMessageWithAgentCLIKit(
            message,
            initialGoal: initialGoal,
            conversationId: conversationId,
            activityVisibility: activityVisibility
        )
    }

    func sendSteeringMessage(
        _ message: String,
        conversationId: String,
        steeringInputID: String
    ) async throws {
        try await sendMessageWithAgentCLIKit(
            message,
            conversationId: conversationId,
            activityVisibility: .visible,
            metadata: [
                AgentCLIKit.AgentSteeringMetadata.isSteering: .bool(true),
                AgentCLIKit.AgentSteeringMetadata.inputId: .string(steeringInputID)
            ]
        )
    }

    func cancelTurn(conversationId: String) {
        cancelTurnWithAgentCLIKit(conversationId: conversationId)
    }

    func destroyRuntime(conversationId: String) async throws {
        try await destroyRuntimeWithAgentCLIKit(conversationId: conversationId, timeout: .seconds(7))
    }

    func kill(conversationId: String) {
        killWithAgentCLIKit(conversationId: conversationId)
    }

    func killAll() {
        killAllWithAgentCLIKit()
    }

    @discardableResult
    func reconfigureSession(conversationId: String, config: AgentSpawnConfig) async throws -> AgentSessionReconfigureResult {
        try await reconfigureSessionWithAgentCLIKit(conversationId: conversationId, config: config)
    }

    func startFreshSession(conversationId: String, config: AgentSpawnConfig) async throws {
        try await startFreshSessionWithAgentCLIKit(conversationId: conversationId, config: config)
    }

    /// Removes Alveary's session binding and any reusable approvals tied to that provider session.
    func finalizeSessionRemoval(for conversationId: String) async {
        if await sessionManager.hasSession(for: conversationId) {
            let sessionId = await sessionManager.sessionId(for: conversationId)
            await claudeApprovalPersistenceStore.removeSessionApprovals(
                providerId: "claude",
                conversationId: conversationId,
                sessionId: sessionId
            )
        }
        do {
            try await sessionManager.removeEntry(for: conversationId)
        } catch {
            pendingSessionRemovalErrors[conversationId] = error.localizedDescription
        }
        pendingSessionRemovalIds.remove(conversationId)
    }

    /// Updates Alveary's local session binding and clears durable approvals for the replaced provider session.
    func updateConversationSessionID(
        _ sessionId: String,
        conversationId: String
    ) async {
        if await sessionManager.hasSession(for: conversationId) {
            let previousSessionId = await sessionManager.sessionId(for: conversationId)
            if previousSessionId != sessionId {
                await claudeApprovalPersistenceStore.removeSessionApprovals(
                    providerId: "claude",
                    conversationId: conversationId,
                    sessionId: previousSessionId
                )
            }
        }
        do {
            try await sessionManager.updateSessionId(for: conversationId, newSessionId: sessionId)
        } catch {}
    }

    func scheduleBufferCleanup(for id: String, generation expectedGeneration: UUID, delay: Duration = .seconds(300)) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            await self?.runScheduledBufferCleanup(for: id, generation: expectedGeneration)
        }
    }

    func publishManagedProcessesChanged() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .managedProcessesChanged, object: nil)
        }
    }

    private func runScheduledBufferCleanup(for id: String, generation expectedGeneration: UUID) {
        guard !hasRuntimePreventingBufferCleanup(conversationId: id),
              let managedBuffer = eventBuffers[id],
              managedBuffer.generation == expectedGeneration,
              !managedBuffer.buffer.hasSubscribers else {
            return
        }

        if managedBuffer.buffer.hasUnpersistedEvents {
            scheduleBufferCleanup(for: id, generation: expectedGeneration, delay: .seconds(60))
            return
        }

        eventBuffers.removeValue(forKey: id)
    }
}
