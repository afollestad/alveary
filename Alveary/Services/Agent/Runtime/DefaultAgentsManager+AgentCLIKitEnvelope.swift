import AgentCLIKit
import Foundation

extension DefaultAgentsManager {
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
