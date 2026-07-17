import Foundation

extension DefaultVoiceInputService {
    nonisolated func shutdownCaptureSynchronously(for session: VoiceInputRecognitionSession) {
        captureSlot.shutdownSynchronously(for: session)
    }

    nonisolated func cancelCaptureSynchronously(for session: VoiceInputRecognitionSession) {
        captureSlot.cancelSynchronously(for: session)
    }

    nonisolated func prepareForTerminationSynchronously() {
        captureSlot.terminateSynchronously()
        suddenTerminationLease.release()
    }

    #if DEBUG
    nonisolated var terminationWasRequestedForTesting: Bool {
        captureSlot.terminationWasRequested
    }
    #endif
}
