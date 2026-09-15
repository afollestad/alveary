import AgentCLIKit
import Foundation

extension DefaultAgentsManager {
    func recordHarnessSessionBindingIfNeeded(
        from envelope: AgentCLIKit.AgentEventEnvelope,
        conversationId: String,
        workingDirectory: String
    ) async {
        guard let harnessSessionId = envelope.harnessSessionId?.rawValue else {
            return
        }

        let binding = HarnessSessionBinding(
            conversationID: conversationId,
            harnessID: envelope.harnessId.rawValue,
            harnessSessionID: harnessSessionId,
            workingDirectory: workingDirectory
        )
        guard recordedHarnessSessionBindings.insert(binding).inserted else {
            return
        }
        await harnessSessionBindingStore.record(binding)
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
