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
                forkSession: false,
                initialTurnActivityVisibility: .visible
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
            // Off the resolution path: the nudge does transcript file I/O and a stdin write, and the
            // approval result must not wait on either.
            Task { [weak self] in
                await self?.nudgeRespawnIfClaudeDeferredReplayUnavailable(request, services: services)
            }
        } catch {
            if didSpawn {
                await services.runtime.kill(conversationId: services.hostAdapter.conversationId(request.conversationId))
            }
            await discardAgentCLIKitTransientDecisions(approvals, services: services)
            await MainActor.run {
                conversationState(for: request.conversationId).endTurn()
            }
            throw error
        }
    }

    /// Claude only re-runs a deferred tool on resume when its session transcript kept the deferred-tool
    /// marker. A teardown that raced that write resumes as an idle session, so without a nudge the approved
    /// turn would spin forever waiting on a replay that never starts. Best-effort: the approval itself has
    /// already resolved, so a send racing process exit must not fail the resolution.
    private func nudgeRespawnIfClaudeDeferredReplayUnavailable(
        _ request: AgentToolApprovalResolutionRequest,
        services: AgentCLIKitHostServices
    ) async {
        guard request.config.providerId == "claude" else {
            return
        }
        // App-native prompts deliver their answer through the resolution path; a "run it again"
        // user message would inject noise into prompt flows instead of recovering a tool replay.
        guard !request.approval.isAppNativeInteractionPrompt else {
            return
        }
        let reader = AgentCLIKit.ClaudeHookTranscriptReader()
        guard !reader.hasDeferredToolMarker(
            forToolUseId: AgentCLIKit.AgentInteractionID(rawValue: request.approval.toolUseId),
            sessionId: AgentCLIKit.AgentSessionID(rawValue: request.approval.sessionId),
            workingDirectoryPath: request.config.workingDirectory
        ) else {
            return
        }
        let runtimeConversationId = services.hostAdapter.conversationId(request.conversationId)
        guard await services.runtime.status(conversationId: runtimeConversationId)?.isProcessRunning == true else {
            return
        }
        try? await services.runtime.send(
            .userMessage(AgentCLIKit.AgentMessageInput(text: Self.deferredReplayRecoveryMessage(for: request))),
            conversationId: runtimeConversationId
        )
    }

    private static func deferredReplayRecoveryMessage(for request: AgentToolApprovalResolutionRequest) -> String {
        switch request.resolution.decision {
        case .allow:
            return "The pending \(request.approval.toolName) tool use was approved in Alveary, but this session "
                + "could not replay it automatically. Run that tool use again now."
        case .deny:
            return "The pending \(request.approval.toolName) tool use was denied in Alveary. "
                + "Do not retry it; continue without it."
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
                try agentCLIKitInteractionResolution(
                    for: approval,
                    resolution: request.resolution,
                    sessionApproval: request.sessionApproval
                ),
                conversationId: runtimeConversationId
            )
        }
    }

    private func waitForAgentCLIKitDeferredRuntimeStop(
        conversationId: String,
        services: AgentCLIKitHostServices
    ) async throws {
        // AgentCLIKit tears a deferred-stopped process down by closing stdin and only force kills after its
        // grace period. Killing earlier here can race Claude's deferred-tool transcript writes, so wait past
        // that window before escalating.
        let runtimeConversationId = services.hostAdapter.conversationId(conversationId)
        if try await waitForAgentCLIKitProcessStop(
            runtimeConversationId,
            conversationId: conversationId,
            timeout: .seconds(7),
            services: services
        ) {
            return
        }

        await services.runtime.kill(conversationId: runtimeConversationId)
        if try await waitForAgentCLIKitProcessStop(
            runtimeConversationId,
            conversationId: conversationId,
            timeout: .seconds(2),
            services: services
        ) {
            return
        }
        throw AgentError.spawnFailed("Timed out waiting for deferred approval runtime to stop for \(conversationId)")
    }

    private func waitForAgentCLIKitProcessStop(
        _ runtimeConversationId: AgentCLIKit.AgentConversationID,
        conversationId: String,
        timeout: Duration,
        services: AgentCLIKitHostServices
    ) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if let status = await services.runtime.status(conversationId: runtimeConversationId) {
                agentCLIKitStatuses[conversationId] = status
                if !status.isProcessRunning {
                    return true
                }
            } else {
                return true
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        return false
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
            return .deny(reason: agentCLIKitDenyReason(for: approval, resolution: resolution))
        }
    }

    private func agentCLIKitDenyReason(
        for approval: ToolApprovalRequest,
        resolution: ClaudeToolApprovalResolution
    ) -> String {
        if approval.toolName == "ExitPlanMode",
           let responseText = resolution.responseText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !responseText.isEmpty {
            return responseText
        }
        return "The user denied this permission prompt in Alveary"
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
