import Foundation

extension DefaultAgentsManager {
    func stopDeferredRuntimeIfCurrent(
        conversationId: String,
        generation: UUID,
        pid: Int32
    ) async {
        guard let managedBuffer = eventBuffers[conversationId],
              managedBuffer.generation == generation,
              processes[conversationId]?.processIdentifier == pid else {
            return
        }

        suppressExitStatus(for: conversationId, pid: pid)
        await teardownProcess(
            for: conversationId,
            awaitExit: true,
            preserveBufferForDurabilityGrace: false,
            graceSeconds: 1.0
        )
        updateStatus(.stopped, for: conversationId)
    }
}
