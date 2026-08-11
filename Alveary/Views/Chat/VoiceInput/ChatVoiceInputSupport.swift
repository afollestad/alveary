import Foundation

struct StartupRelease {
    let forced: Bool
    let duration: Duration
}
extension Duration {
    func duration(to later: Duration) -> Duration {
        later - self
    }
}

final class DisabledVoiceInputService: VoiceInputService, @unchecked Sendable {
    func admitPreparation(requiringPreparation: Bool) -> VoiceInputPreparationAdmission { .initiated }

    func prepare(
        progress: @escaping VoiceInputPreparationProgressHandler
    ) async throws -> VoiceInputPreparationResult {
        throw VoiceInputServiceError.unsupportedArchitecture
    }

    func beginRecognition(
        attempt: VoiceInputRecognitionAttempt,
        onUpdate: @escaping VoiceInputRecognitionUpdateHandler
    ) async throws -> VoiceInputRecognitionSession {
        throw VoiceInputServiceError.unsupportedArchitecture
    }

    func stopRecognition(_ session: VoiceInputRecognitionSession) async -> VoiceInputRecognitionResult {
        .cancelled
    }

    func cancelRecognition(_ session: VoiceInputRecognitionSession) async {}
    func unloadIfIdle() async {}
    func shutdownCaptureSynchronously(for session: VoiceInputRecognitionSession) {}
    func cancelCaptureSynchronously(for session: VoiceInputRecognitionSession) {}
    func prepareForTerminationSynchronously() {}
    func clearModelCache() async throws {
        throw VoiceInputServiceError.unsupportedArchitecture
    }
    func shutdown() async {}
}
