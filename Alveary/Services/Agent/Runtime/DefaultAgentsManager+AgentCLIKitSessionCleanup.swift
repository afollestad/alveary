import AgentCLIKit
import Foundation

extension DefaultAgentsManager {
    func tearDownAgentCLIKitRuntime(conversationId: String, removeSession: Bool) async {
        let services = agentCLIKitServices
        let runtimeConversationId = services.hostAdapter.conversationId(conversationId)
        let runtimeStatusHarnessId = await services.runtime.status(conversationId: runtimeConversationId)?.harnessId
        let activeHarnessId = agentCLIKitStatuses[conversationId]?.harnessId
            ?? runtimeStatusHarnessId
        agentCLIKitEventTasks.removeValue(forKey: conversationId)?.cancel()
        agentCLIKitStatusTasks.removeValue(forKey: conversationId)?.cancel()
        eventBuffers[conversationId]?.allowsReplay = false
        eventBuffers[conversationId]?.acceptsLiveEvents = false
        eventBuffers[conversationId]?.buffer.finishAll()
        await services.liveHookDecisionProvider.discardDecisions(conversationId: conversationId)
        await services.runtime.destroy(conversationId: runtimeConversationId)
        if removeSession {
            do {
                try await removeAgentCLIKitSessionRecord(
                    conversationId: runtimeConversationId,
                    activeHarnessId: activeHarnessId,
                    services: services
                )
            } catch {
                pendingSessionRemovalErrors[conversationId] = error.localizedDescription
            }
        }
        agentCLIKitStatuses.removeValue(forKey: conversationId)
        // The status task was cancelled above, so the final zero-count status may never arrive.
        await MainActor.run {
            let state = conversationStatesStore.withLock { $0[conversationId] }
            state?.liveBackgroundTaskCount = 0
        }
        agentCLIKitGenerationByConversation.removeValue(forKey: conversationId)
        agentCLIKitGenerationUUIDs.removeValue(forKey: conversationId)
        cancelledInteractionsByConversation.removeValue(forKey: conversationId)
        if removeSession || !pendingKillIds.contains(conversationId) {
            closingConversationIds.remove(conversationId)
            pendingSessionRemovalIds.remove(conversationId)
        }
        clearStatus(for: conversationId)
    }

    func removeAgentCLIKitSessionRecord(
        conversationId: AgentCLIKit.AgentConversationID,
        activeHarnessId: AgentCLIKit.AgentHarnessID?,
        services: AgentCLIKitHostServices
    ) async throws {
        if let activeHarnessId {
            try await removeAgentCLIKitSessionApprovals(
                conversationId: conversationId,
                harnessId: activeHarnessId,
                services: services
            )
            try await services.sessionStore.remove(
                conversationId: conversationId,
                harnessId: activeHarnessId
            )
            return
        }

        let harnessIds = await services.harnessRegistry.allDefinitions().map(\.id)
        for harnessId in harnessIds {
            try await removeAgentCLIKitSessionApprovals(
                conversationId: conversationId,
                harnessId: harnessId,
                services: services
            )
            try await services.sessionStore.remove(
                conversationId: conversationId,
                harnessId: harnessId
            )
        }
    }

    /// Removes reusable approvals for the `AgentCLIKit` session record before the record is deleted.
    func removeAgentCLIKitSessionApprovals(
        conversationId: AgentCLIKit.AgentConversationID,
        harnessId: AgentCLIKit.AgentHarnessID,
        services: AgentCLIKitHostServices
    ) async throws {
        guard let record = try await services.sessionStore.record(
            conversationId: conversationId,
            harnessId: harnessId
        ) else {
            return
        }
        await services.claudeApprovalPolicyStore.removeSessionApprovals(
            harnessId: record.harnessId,
            conversationId: record.conversationId,
            sessionId: record.harnessSessionId
        )
    }
}
