import AgentCLIKit
import Foundation

extension DefaultAgentsManager {
    func shouldResumeAgentCLIKitDeferredApproval(conversationId: String) -> Bool {
        eventBuffers[conversationId]?.hasDeferredToolStop == true &&
            status(for: conversationId) == .waitingForUser
    }

    func canResumeAgentCLIKitDeferredApproval(
        conversationId: String,
        services: AgentCLIKitHostServices
    ) async -> Bool {
        if shouldResumeAgentCLIKitDeferredApproval(conversationId: conversationId) {
            return true
        }
        return await canResumeRestoredAgentCLIKitApproval(
            conversationId: conversationId,
            services: services
        )
    }

    private func canResumeRestoredAgentCLIKitApproval(
        conversationId: String,
        services: AgentCLIKitHostServices
    ) async -> Bool {
        guard !spawningIds.contains(conversationId),
              !reconfiguringIds.contains(conversationId) else {
            return false
        }

        let runtimeConversationId = services.hostAdapter.conversationId(conversationId)
        if let status = await services.runtime.status(conversationId: runtimeConversationId) {
            agentCLIKitStatuses[conversationId] = status
            return !status.isProcessRunning
        }

        return agentCLIKitStatuses[conversationId]?.isProcessRunning != true
    }

    func resumeAgentCLIKitDeferredApproval(
        _ request: AgentToolApprovalResolutionRequest,
        approvals: [ToolApprovalRequest],
        services: AgentCLIKitHostServices
    ) async throws {
        try await waitForAgentCLIKitDeferredRuntimeStop(
            conversationId: request.conversationId,
            services: services
        )
        try await recordAgentCLIKitTransientDecisions(
            approvals,
            resolution: request.resolution,
            services: services
        )
        var didSpawn = false
        do {
            await MainActor.run {
                conversationState(for: request.conversationId).turnState.beginTurn()
            }
            try await spawnWithAgentCLIKit(
                id: request.conversationId,
                config: request.config,
                forkSession: false
            )
            didSpawn = true
            // Transient hook decisions cover hook callbacks, but a deferred respawn can also leave the new
            // AgentCLIKit process waiting on stdin interaction resolutions. Send them for every fallback
            // respawn, not only restore-time resumes, so parallel approvals cannot render approved while stuck.
            try await resolveRespawnedAgentCLIKitInteractionsIfRunning(
                request,
                approvals: approvals,
                services: services
            )
        } catch {
            if didSpawn {
                await services.runtime.kill(conversationId: services.hostAdapter.conversationId(request.conversationId))
            }
            await discardAgentCLIKitTransientDecisions(approvals, services: services)
            await MainActor.run {
                conversationState(for: request.conversationId).turnState.endTurn()
            }
            throw error
        }
    }

    private func resolveRespawnedAgentCLIKitInteractionsIfRunning(
        _ request: AgentToolApprovalResolutionRequest,
        approvals: [ToolApprovalRequest],
        services: AgentCLIKitHostServices
    ) async throws {
        let runtimeConversationId = services.hostAdapter.conversationId(request.conversationId)
        guard await services.runtime.status(conversationId: runtimeConversationId)?.isProcessRunning == true else {
            return
        }
        for approval in approvals {
            try await services.runtime.resolveInteraction(
                try agentCLIKitInteractionResolution(for: approval, resolution: request.resolution),
                conversationId: runtimeConversationId
            )
        }
    }

    private func waitForAgentCLIKitDeferredRuntimeStop(
        conversationId: String,
        services: AgentCLIKitHostServices
    ) async throws {
        let runtimeConversationId = services.hostAdapter.conversationId(conversationId)
        if await services.runtime.status(conversationId: runtimeConversationId)?.isProcessRunning == true {
            await services.runtime.kill(conversationId: runtimeConversationId)
        }

        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while clock.now < deadline {
            if let status = await services.runtime.status(conversationId: runtimeConversationId) {
                agentCLIKitStatuses[conversationId] = status
                if !status.isProcessRunning {
                    return
                }
            } else {
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw AgentError.spawnFailed("Timed out waiting for deferred approval runtime to stop for \(conversationId)")
    }

    func stopAgentCLIKitDeferredRuntimeIfCurrent(conversationId: String, generation: UUID) async {
        guard let services = agentCLIKitServices,
              let managedBuffer = eventBuffers[conversationId],
              managedBuffer.generation == generation,
              managedBuffer.hasDeferredToolStop else {
            return
        }
        let runtimeConversationId = services.hostAdapter.conversationId(conversationId)
        guard await services.runtime.status(conversationId: runtimeConversationId)?.isProcessRunning == true else {
            return
        }
        await services.runtime.kill(conversationId: runtimeConversationId)
    }

    private func recordAgentCLIKitTransientDecisions(
        _ approvals: [ToolApprovalRequest],
        resolution: ClaudeToolApprovalResolution,
        services: AgentCLIKitHostServices
    ) async throws {
        let decisions = try approvals.map { approval in
            (
                key: agentCLIKitTransientDecisionKey(for: approval),
                decision: try agentCLIKitHookDecision(for: approval, resolution: resolution)
            )
        }
        for decision in decisions {
            await services.claudeApprovalPolicyStore.recordTransientDecision(
                decision.decision,
                for: decision.key
            )
        }
    }

    private func discardAgentCLIKitTransientDecisions(
        _ approvals: [ToolApprovalRequest],
        services: AgentCLIKitHostServices
    ) async {
        for approval in approvals {
            await services.claudeApprovalPolicyStore.discardTransientDecision(
                for: agentCLIKitTransientDecisionKey(for: approval)
            )
        }
    }

    private func agentCLIKitTransientDecisionKey(for approval: ToolApprovalRequest) -> AgentCLIKit.ClaudeTransientDecisionKey {
        AgentCLIKit.ClaudeTransientDecisionKey(
            sessionId: AgentCLIKit.AgentSessionID(rawValue: approval.sessionId),
            interactionId: AgentCLIKit.AgentInteractionID(rawValue: approval.toolUseId)
        )
    }

    private func agentCLIKitHookDecision(
        for approval: ToolApprovalRequest,
        resolution: ClaudeToolApprovalResolution
    ) throws -> AgentCLIKit.ClaudeHookDecision {
        switch resolution.decision {
        case .allow:
            return .allow(
                reason: "The user approved this permission prompt in Alveary",
                updatedInput: try agentCLIKitUpdatedInput(for: approval, resolution: resolution)
            )
        case .deny:
            return .deny(reason: "The user denied this permission prompt in Alveary")
        }
    }

    private func agentCLIKitUpdatedInput(
        for approval: ToolApprovalRequest,
        resolution: ClaudeToolApprovalResolution
    ) throws -> AgentCLIKit.JSONValue? {
        if let updatedInput = resolution.updatedInput {
            return try agentCLIKitJSONValue(from: updatedInput)
        }
        switch approval.toolName {
        case "AskUserQuestion", "ExitPlanMode":
            return try agentCLIKitJSONValue(from: approval.toolInput)
        default:
            return nil
        }
    }
}
