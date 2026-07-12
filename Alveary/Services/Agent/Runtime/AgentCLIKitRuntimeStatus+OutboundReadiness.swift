import AgentCLIKit
import Foundation

extension DefaultAgentsManager {
    func handleAgentCLIKitDeferredKillAfterSpawn(for conversationId: String) {
        guard pendingKillIds.remove(conversationId) != nil else {
            return
        }
        Task {
            await tearDownAgentCLIKitRuntime(conversationId: conversationId, removeSession: true)
        }
    }

    func outboundReadiness(conversationId: String) async -> AgentOutboundReadiness {
        while true {
            if let blocked = outboundLifecycleBlock(conversationId: conversationId) {
                return blocked
            }
            guard await waitForSuspensionToFinish(conversationId: conversationId) else {
                return outboundLifecycleBlock(conversationId: conversationId) ??
                    .blocked(reason: "Session changes are still being applied")
            }
            if let blocked = outboundLifecycleBlock(conversationId: conversationId) {
                return blocked
            }
            guard !spawningIds.contains(conversationId),
                  !reconfiguringIds.contains(conversationId) else {
                return .blocked(reason: "Session changes are still being applied")
            }

            let services = agentCLIKitServices
            let runtimeConversationId = services.hostAdapter.conversationId(conversationId)
            let status = await services.runtime.status(conversationId: runtimeConversationId)
            if let blocked = outboundLifecycleBlock(conversationId: conversationId) {
                return blocked
            }
            if suspendingIds.contains(conversationId) {
                continue
            }
            guard !spawningIds.contains(conversationId),
                  !reconfiguringIds.contains(conversationId) else {
                return .blocked(reason: "Session changes are still being applied")
            }
            guard let status else {
                agentCLIKitStatuses.removeValue(forKey: conversationId)
                return .respawnRequired
            }

            agentCLIKitStatuses[conversationId] = status
            return agentCLIKitOutboundReadiness(for: status)
        }
    }

    private func waitForSuspensionToFinish(conversationId: String) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(7)
        while suspendingIds.contains(conversationId) {
            guard !shutdownRequested.withLock({ $0 }),
                  !closingConversationIds.contains(conversationId),
                  clock.now < deadline,
                  !Task.isCancelled else {
                return false
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return outboundLifecycleBlock(conversationId: conversationId) == nil &&
            !suspendingIds.contains(conversationId)
    }

    private func outboundLifecycleBlock(conversationId: String) -> AgentOutboundReadiness? {
        if Task.isCancelled {
            return .blocked(reason: "Outbound request was cancelled")
        }
        if shutdownRequested.withLock({ $0 }) {
            return .blocked(reason: "App is shutting down")
        }
        if closingConversationIds.contains(conversationId) {
            return .blocked(reason: "Conversation is closing")
        }
        return nil
    }
}

func agentCLIKitOutboundReadiness(for status: AgentCLIKit.AgentRuntimeStatus) -> AgentOutboundReadiness {
    if let waitingBlock = outboundWaitingBlock(for: status.waitingState) {
        return waitingBlock
    }
    if status.isTerminal {
        return .respawnRequired
    }
    guard status.state == .running else {
        return .blocked(reason: "Agent process is starting")
    }
    switch status.inputAvailability {
    case .available:
        return status.isProcessRunning ? .ready : .respawnRequired
    case .blocked(let reason):
        return .blocked(reason: reason)
    }
}

private func outboundWaitingBlock(for waitingState: AgentCLIKit.AgentRuntimeWaitingState) -> AgentOutboundReadiness? {
    switch waitingState {
    case .approval:
        return .blocked(reason: "Approve or deny the pending tool use before sending another message")
    case .prompt:
        return .blocked(reason: "Answer the pending question before sending another message")
    case .planModeExit:
        return .blocked(reason: "Wait for the plan response before sending another message")
    case .idle:
        return nil
    }
}

extension AgentCLIKit.AgentRuntimeStatus {
    var isTerminal: Bool {
        switch state {
        case .cancelled, .exited, .failed:
            return true
        case .starting, .running:
            return false
        }
    }

    var isActiveRuntimePreventingReplacement: Bool {
        !isTerminal && isProcessRunning
    }
}
