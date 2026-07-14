import AgentCLIKit
import Foundation

extension DefaultAgentsManager {
    func recordProviderSessionBindingIfNeeded(
        from envelope: AgentCLIKit.AgentEventEnvelope,
        conversationId: String,
        workingDirectory: String
    ) async {
        guard let providerSessionId = envelope.providerSessionId?.rawValue else {
            return
        }

        let binding = ProviderSessionBinding(
            conversationID: conversationId,
            providerID: envelope.providerId.rawValue,
            providerSessionID: providerSessionId,
            workingDirectory: workingDirectory
        )
        guard recordedProviderSessionBindings.insert(binding).inserted else {
            return
        }
        await providerSessionBindingStore.record(binding)
    }

    func recordAgentCLIKitEnvelopeIndex(
        _ envelopeIndex: Int,
        conversationId: String,
        generation: UUID
    ) {
        guard let managedBuffer = eventBuffers[conversationId],
              managedBuffer.generation == generation else {
            return
        }
        managedBuffer.recordAgentCLIKitEnvelopeIndex(envelopeIndex)
    }
}

extension AgentCLIKit.AgentEventEnvelope {
    var isHostToolServerUnavailableDiagnostic: Bool {
        guard case let .diagnostic(event) = event else {
            return false
        }
        return event.code == .hostToolServerUnavailable
    }

    var isRuntimeStartLifecycle: Bool {
        guard case let .lifecycle(event) = event else {
            return false
        }
        return event.state == .starting || event.state == .running
    }

    var isTerminalLifecycle: Bool {
        guard case let .lifecycle(event) = event else {
            return false
        }
        switch event.state {
        case .cancelled, .exited, .failed:
            return true
        case .starting, .running:
            return false
        }
    }
}
