import AgentCLIKit
import Foundation

extension DefaultAgentsManager {
    func previousAgentCLIKitSessionRecord(
        conversationId: AgentCLIKit.AgentConversationID,
        providerId rawProviderId: String,
        services: AgentCLIKitHostServices
    ) async throws -> AgentCLIKit.AgentSessionRecord? {
        guard let providerId = services.hostAdapter.providerId(rawProviderId) else {
            throw AgentCLIKitHostAdapterError.unsupportedProvider(rawProviderId)
        }
        return try await services.sessionStore.record(
            conversationId: conversationId,
            providerId: providerId
        )
    }

    func removePreviousAgentCLIKitSessionState(
        _ previousSessionRecord: AgentCLIKit.AgentSessionRecord?,
        services: AgentCLIKitHostServices
    ) async {
        guard let previousSessionRecord else {
            return
        }
        await services.claudeApprovalPolicyStore.removeSessionApprovals(
            providerId: previousSessionRecord.providerId,
            conversationId: previousSessionRecord.conversationId,
            sessionId: previousSessionRecord.providerSessionId
        )
        do {
            let currentRecord = try await services.sessionStore.record(
                conversationId: previousSessionRecord.conversationId,
                providerId: previousSessionRecord.providerId
            )
            guard currentRecord?.providerSessionId == previousSessionRecord.providerSessionId else {
                return
            }
            await archivePreviousAgentCLIKitProviderSession(previousSessionRecord, services: services)
            try await services.sessionStore.remove(
                conversationId: previousSessionRecord.conversationId,
                providerId: previousSessionRecord.providerId
            )
        } catch {
            pendingSessionRemovalErrors[previousSessionRecord.conversationId.rawValue] = error.localizedDescription
        }
    }

    /// Archives the provider session a handoff is dropping, along with everything it superseded.
    ///
    /// A handoff spawns fresh, so the runtime never sees this session replaced and never records it in a lineage.
    /// Removing its record right after would leave it — and its whole lineage — live with nothing left pointing at
    /// them. Best effort: the handoff already succeeded, so a provider failure must not fail or undo it.
    private func archivePreviousAgentCLIKitProviderSession(
        _ previousSessionRecord: AgentCLIKit.AgentSessionRecord,
        services: AgentCLIKitHostServices
    ) async {
        guard let definition = await services.providerRegistry.definition(for: previousSessionRecord.providerId),
              definition.capabilities.supportsSessionArchiving else {
            return
        }
        do {
            try await services.sessionActionRouter.archiveSession(previousSessionRecord)
        } catch {
            pendingSessionRemovalErrors[previousSessionRecord.conversationId.rawValue] = error.localizedDescription
        }
    }
}
