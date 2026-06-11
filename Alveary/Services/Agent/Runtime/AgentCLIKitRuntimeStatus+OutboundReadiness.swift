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
        guard !shutdownRequested.withLock({ $0 }) else {
            return .blocked(reason: "App is shutting down")
        }
        guard !closingConversationIds.contains(conversationId) else {
            return .blocked(reason: "Conversation is closing")
        }
        guard !spawningIds.contains(conversationId),
              !reconfiguringIds.contains(conversationId) else {
            return .blocked(reason: "Session changes are still being applied")
        }

        let services = agentCLIKitServices
        let runtimeConversationId = services.hostAdapter.conversationId(conversationId)
        guard let status = await services.runtime.status(conversationId: runtimeConversationId) else {
            agentCLIKitStatuses.removeValue(forKey: conversationId)
            return .respawnRequired
        }

        agentCLIKitStatuses[conversationId] = status
        return agentCLIKitOutboundReadiness(for: status)
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
