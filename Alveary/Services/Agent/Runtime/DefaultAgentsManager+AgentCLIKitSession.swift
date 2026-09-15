import AgentCLIKit
import Foundation

extension DefaultAgentsManager {
    func previousAgentCLIKitSessionRecord(
        conversationId: AgentCLIKit.AgentConversationID,
        harnessId rawHarnessId: String,
        services: AgentCLIKitHostServices
    ) async throws -> AgentCLIKit.AgentSessionRecord? {
        guard let harnessId = services.hostAdapter.harnessId(rawHarnessId) else {
            throw AgentCLIKitHostAdapterError.unsupportedHarness(rawHarnessId)
        }
        return try await services.sessionStore.record(
            conversationId: conversationId,
            harnessId: harnessId
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
            harnessId: previousSessionRecord.harnessId,
            conversationId: previousSessionRecord.conversationId,
            sessionId: previousSessionRecord.harnessSessionId
        )
        do {
            let currentRecord = try await services.sessionStore.record(
                conversationId: previousSessionRecord.conversationId,
                harnessId: previousSessionRecord.harnessId
            )
            guard currentRecord?.harnessSessionId == previousSessionRecord.harnessSessionId else {
                return
            }
            await archivePreviousAgentCLIKitHarnessSession(previousSessionRecord, services: services)
            try await services.sessionStore.remove(
                conversationId: previousSessionRecord.conversationId,
                harnessId: previousSessionRecord.harnessId
            )
        } catch {
            pendingSessionRemovalErrors[previousSessionRecord.conversationId.rawValue] = error.localizedDescription
        }
    }

    /// Archives the harness session a handoff is dropping, along with everything it superseded.
    ///
    /// A handoff spawns fresh, so the runtime never sees this session replaced and never records it in a lineage.
    /// Removing its record right after would leave it — and its whole lineage — live with nothing left pointing at
    /// them. Best effort: the handoff already succeeded, so a harness failure must not fail or undo it.
    private func archivePreviousAgentCLIKitHarnessSession(
        _ previousSessionRecord: AgentCLIKit.AgentSessionRecord,
        services: AgentCLIKitHostServices
    ) async {
        guard let definition = await services.harnessRegistry.definition(for: previousSessionRecord.harnessId),
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
