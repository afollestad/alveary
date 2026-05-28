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
            try await services.sessionStore.remove(
                conversationId: previousSessionRecord.conversationId,
                providerId: previousSessionRecord.providerId
            )
        } catch {
            pendingSessionRemovalErrors[previousSessionRecord.conversationId.rawValue] = error.localizedDescription
        }
    }
}
