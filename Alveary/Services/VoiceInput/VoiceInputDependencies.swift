@preconcurrency import AVFoundation
import Foundation

typealias VoiceInputPreparationProgressHandler = @Sendable (VoiceInputPreparationProgress) -> Void
typealias VoiceInputRecognitionUpdateHandler = @Sendable (VoiceInputRecognitionUpdate) -> Void

protocol VoiceInputService: AnyObject, Sendable {
    func admitPreparation(requiringPreparation: Bool) -> VoiceInputPreparationAdmission
    func prepare(progress: @escaping VoiceInputPreparationProgressHandler) async throws -> VoiceInputPreparationResult
    func beginRecognition(
        attempt: VoiceInputRecognitionAttempt,
        onUpdate: @escaping VoiceInputRecognitionUpdateHandler
    ) async throws -> VoiceInputRecognitionSession
    func stopRecognition(_ session: VoiceInputRecognitionSession) async -> VoiceInputRecognitionResult
    func cancelRecognition(_ session: VoiceInputRecognitionSession) async
    func unloadIfIdle() async
    func shutdownCaptureSynchronously(for session: VoiceInputRecognitionSession)
    func cancelCaptureSynchronously(for session: VoiceInputRecognitionSession)
    func prepareForTerminationSynchronously()
    func clearModelCache() async throws
    func shutdown() async
}

extension VoiceInputService {
    func admitPreparation() -> VoiceInputPreparationAdmission {
        admitPreparation(requiringPreparation: false)
    }
}

protocol VoiceInputPermissionProviding: Sendable {
    func authorizationStatus() -> VoiceInputPermissionStatus
    func requestAccess() async -> Bool
}

struct AVCaptureVoiceInputPermissionProvider: VoiceInputPermissionProviding {
    func authorizationStatus() -> VoiceInputPermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            .notDetermined
        case .authorized:
            .authorized
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .restricted
        }
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}

protocol VoiceInputModelRepository: Sendable {
    func prepareModel(
        mode: VoiceInputModelPreparationMode,
        progress: @escaping VoiceInputPreparationProgressHandler
    ) async throws -> VoiceInputPreparedModel
    func purgeValidatedModel() async throws
    func removeUnpinnedModels() async throws
    func purgeAllModels() async throws
}

protocol VoiceInputInferenceEngine: Sendable {
    func loadModels(from directory: URL) async throws
    func reset() async throws
    func process(_ buffer: VoiceInputPCMTransfer) async throws -> String
    func finishAndReset() async throws -> VoiceInputInferenceFinalization
    func cancelAndReset() async -> Bool
    func cleanup() async
}

struct VoiceInputInferenceFinalization: Equatable, Sendable {
    let transcript: String
    let isReusable: Bool
}

struct VoiceInputInferenceOperationError: LocalizedError, Sendable {
    let message: String
    let isReusable: Bool

    var errorDescription: String? { message }
}

enum VoiceInputCaptureEvent: Sendable {
    case audio(VoiceInputPCMTransfer)
    case failed(VoiceInputServiceError)
}

protocol VoiceInputAudioCapturing: AnyObject, Sendable {
    func start(
        generation: UInt64,
        consumer: @escaping @Sendable (VoiceInputCaptureEvent) async -> Void
    ) throws
    func stopAndDrain() async
    func stopAndDiscard() async
    // Synchronous teardown permanently closes this single-use capture, including before `start` enters.
    func shutdownSynchronously()
    func shutdownAndDiscardSynchronously()
}

typealias VoiceInputAudioCaptureFactory = @Sendable () -> any VoiceInputAudioCapturing

protocol VoiceInputSuddenTerminationControlling: Sendable {
    func disable()
    func enable()
}

struct ProcessSuddenTerminationController: VoiceInputSuddenTerminationControlling {
    func disable() {
        ProcessInfo.processInfo.disableSuddenTermination()
    }

    func enable() {
        ProcessInfo.processInfo.enableSuddenTermination()
    }
}

protocol VoiceInputMemoryPressureMonitoring: AnyObject, Sendable {
    func start(handler: @escaping @Sendable () -> Void)
    func stop()
}

final class DispatchMemoryPressureMonitor: VoiceInputMemoryPressureMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var source: DispatchSourceMemoryPressure?

    func start(handler: @escaping @Sendable () -> Void) {
        lock.withLock {
            guard source == nil else { return }
            let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
            source.setEventHandler(handler: handler)
            self.source = source
            source.resume()
        }
    }

    func stop() {
        let source = lock.withLock { () -> DispatchSourceMemoryPressure? in
            defer { self.source = nil }
            return self.source
        }
        source?.cancel()
    }

    deinit {
        stop()
    }
}
