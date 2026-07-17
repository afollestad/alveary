import Foundation

typealias VoiceInputArchitectureCheck = @Sendable () -> Bool

final class VoiceInputPreparationBroadcast: @unchecked Sendable {
    private struct State {
        var observers: [UUID: VoiceInputPreparationProgressHandler] = [:]
        var isActive = false
        var modelIsReady = false
        var modelGeneration: UInt64 = 0
        var hasPendingAdmission = false
        var hasParticipant = false
    }

    private let lock = NSLock()
    private var state = State()

    func admitPreparation(requiringPreparation: Bool) -> VoiceInputPreparationAdmission {
        lock.withLock {
            guard !state.isActive,
                  !state.hasPendingAdmission,
                  !state.hasParticipant else {
                return .busy
            }
            if state.modelIsReady, !requiringPreparation {
                return .ready
            }
            state.hasPendingAdmission = true
            return .initiated
        }
    }

    func beginParticipant() -> Bool {
        lock.withLock {
            guard state.hasPendingAdmission,
                  !state.isActive,
                  !state.hasParticipant else {
                return false
            }
            state.hasPendingAdmission = false
            state.hasParticipant = true
            return true
        }
    }

    func endParticipant() {
        lock.withLock {
            state.hasParticipant = false
        }
    }

    func setModelIsReady(_ isReady: Bool) {
        lock.withLock {
            if isReady, !state.modelIsReady {
                state.modelGeneration &+= 1
            }
            state.modelIsReady = isReady
        }
    }

    func readyModelGenerationForMemoryPressure() -> UInt64? {
        lock.withLock {
            guard state.modelIsReady,
                  !state.isActive,
                  !state.hasPendingAdmission,
                  !state.hasParticipant else {
                return nil
            }
            return state.modelGeneration
        }
    }

    func isCurrentReadyModelGeneration(_ generation: UInt64) -> Bool {
        lock.withLock {
            state.modelIsReady &&
                state.modelGeneration == generation &&
                !state.isActive &&
                !state.hasPendingAdmission &&
                !state.hasParticipant
        }
    }

    func addObserver(_ observer: @escaping VoiceInputPreparationProgressHandler) -> UUID {
        let token = UUID()
        lock.withLock {
            state.observers[token] = observer
        }
        return token
    }

    func removeObserver(_ token: UUID) {
        _ = lock.withLock {
            state.observers.removeValue(forKey: token)
        }
    }

    func begin() {
        lock.withLock {
            state.isActive = true
        }
    }

    func publish(_ progress: VoiceInputPreparationProgress) {
        let observers = lock.withLock { () -> [VoiceInputPreparationProgressHandler] in
            return Array(state.observers.values)
        }
        observers.forEach { $0(progress) }
    }

    func end() {
        lock.withLock {
            state.isActive = false
        }
    }

    var isBusyForCacheClear: Bool {
        lock.withLock {
            state.isActive || state.hasPendingAdmission || state.hasParticipant
        }
    }
}

@discardableResult
func ensureVoiceInputMicrophonePermission(
    permissionProvider: any VoiceInputPermissionProviding,
    canRequestAccess: Bool
) async throws -> Bool {
    switch permissionProvider.authorizationStatus() {
    case .authorized:
        return false
    case .notDetermined:
        guard canRequestAccess else {
            throw VoiceInputServiceError.permissionNotDetermined
        }
        guard await permissionProvider.requestAccess() else {
            throw VoiceInputServiceError.permissionDenied
        }
        return true
    case .denied:
        throw VoiceInputServiceError.permissionDenied
    case .restricted:
        throw VoiceInputServiceError.permissionRestricted
    }
}

func isVoiceInputArchitectureSupported() -> Bool {
    #if arch(arm64)
    true
    #else
    false
    #endif
}

func usableVoiceInputTranscript(_ transcript: String?) -> String? {
    guard let transcript else { return nil }
    return transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : transcript
}

func mappedVoiceInputError(_ error: Error, fallback: VoiceInputServiceError) -> VoiceInputServiceError {
    (error as? VoiceInputServiceError) ?? fallback
}

func cleanupVoiceInputInferenceIfNeeded(
    _ inferenceEngine: any VoiceInputInferenceEngine,
    isReusable: Bool
) async -> Bool {
    guard !isReusable else { return true }
    await inferenceEngine.cleanup()
    return false
}

func throwVoiceInputModelLoadCancellation(
    afterCleaning inferenceEngine: any VoiceInputInferenceEngine
) async throws -> Never {
    await inferenceEngine.cleanup()
    throw CancellationError()
}

func loadVoiceInputModelsWithRepair(
    prepared: VoiceInputPreparedModel,
    inferenceEngine: any VoiceInputInferenceEngine,
    modelRepository: any VoiceInputModelRepository,
    progress: @escaping VoiceInputPreparationProgressHandler,
    broadcast: VoiceInputPreparationBroadcast
) async throws -> VoiceInputPreparedModel.Source {
    broadcast.publish(.loadingModel)
    do {
        try await inferenceEngine.loadModels(from: prepared.repositoryDirectory)
    } catch let error where VoiceInputModelFileError.isCancellation(error) {
        try await throwVoiceInputModelLoadCancellation(afterCleaning: inferenceEngine)
    } catch {
        broadcast.publish(.downloading(kind: .repair, fraction: nil))
        await inferenceEngine.cleanup()
        try Task.checkCancellation()
        try await modelRepository.purgeValidatedModel()
        let repaired = try await modelRepository.prepareModel(mode: .repair, progress: progress)
        broadcast.publish(.loadingModel)
        do {
            try await inferenceEngine.loadModels(from: repaired.repositoryDirectory)
        } catch let error where VoiceInputModelFileError.isCancellation(error) {
            try await throwVoiceInputModelLoadCancellation(afterCleaning: inferenceEngine)
        } catch {
            await inferenceEngine.cleanup()
            try Task.checkCancellation()
            do {
                try await modelRepository.purgeValidatedModel()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Preserve the model-load error as the user-facing failure.
            }
            try Task.checkCancellation()
            throw VoiceInputServiceError.modelLoad(error.localizedDescription)
        }
        return .downloaded(.repair)
    }
    return prepared.source
}

func cancelAndRecoverVoiceInputInference(
    _ inferenceEngine: any VoiceInputInferenceEngine
) async -> Bool {
    let isReusable = await inferenceEngine.cancelAndReset()
    return await cleanupVoiceInputInferenceIfNeeded(inferenceEngine, isReusable: isReusable)
}

func recoverVoiceInputInference(
    _ inferenceEngine: any VoiceInputInferenceEngine,
    after error: Error,
    wasLoaded: Bool
) async -> Bool {
    guard let operationError = error as? VoiceInputInferenceOperationError else {
        return wasLoaded
    }
    return await cleanupVoiceInputInferenceIfNeeded(
        inferenceEngine,
        isReusable: operationError.isReusable
    ) && wasLoaded
}

struct ActiveRecognition {
    struct TerminalFailure {
        let error: VoiceInputServiceError
        let inferenceFailure: Bool
    }

    let session: VoiceInputRecognitionSession
    let generation: UInt64
    let capture: any VoiceInputAudioCapturing
    let finalizationGate: VoiceInputRecognitionFinalizationGate
    let onUpdate: VoiceInputRecognitionUpdateHandler
    var latestPartial: String?
    var pendingTerminalFailure: TerminalFailure?
    var deliverPartials = true
    var finalizing = false
}

final class VoiceInputRecognitionFinalizationGate: @unchecked Sendable {
    private enum State: Equatable {
        case active
        case cancellationRequested
        case finishClaimed
    }

    private let lock = NSLock()
    private var state = State.active

    /// Returns `true` only for the request that wins before final inference is claimed.
    func requestCancellation() -> Bool {
        lock.withLock {
            guard state == .active else { return false }
            state = .cancellationRequested
            return true
        }
    }

    /// Atomically closes the final cancellation window immediately before inference finish.
    func claimFinish() -> Bool {
        lock.withLock {
            guard state == .active else { return false }
            state = .finishClaimed
            return true
        }
    }

    var cancellationWasRequested: Bool {
        lock.withLock { state == .cancellationRequested }
    }
}

final class VoiceInputCaptureSlot: @unchecked Sendable {
    struct StartContext {
        let attemptID: UUID
        let session: VoiceInputRecognitionSession
        let generation: UInt64
        let finalizationGate: VoiceInputRecognitionFinalizationGate
    }

    private struct Reservation {
        let attemptID: UUID
        let generation: UInt64
    }

    private struct ActiveCapture {
        let attemptID: UUID
        let session: VoiceInputRecognitionSession
        let capture: any VoiceInputAudioCapturing
        let finalizationGate: VoiceInputRecognitionFinalizationGate
    }

    private let lock = NSLock()
    private let terminationLock = NSLock()
    private var reservation: Reservation?
    private var activeCapture: ActiveCapture?
    private var terminationRequested = false

    var terminationWasRequested: Bool {
        isTerminationRequested()
    }

    func reserve(attemptID: UUID, generation: UInt64) -> Bool {
        lock.withLock {
            guard !isTerminationRequested(),
                  activeCapture == nil,
                  reservation == nil else {
                return false
            }
            reservation = Reservation(attemptID: attemptID, generation: generation)
            return true
        }
    }

    func start(
        _ capture: any VoiceInputAudioCapturing,
        context: StartContext,
        onAdmission: () -> Void = {},
        operation: () throws -> Void
    ) throws -> Bool {
        let admitted = lock.withLock { () -> Bool in
            guard !isTerminationRequested(),
                  reservation?.attemptID == context.attemptID,
                  reservation?.generation == context.generation else {
                return false
            }
            activeCapture = ActiveCapture(
                attemptID: context.attemptID,
                session: context.session,
                capture: capture,
                finalizationGate: context.finalizationGate
            )
            // Keep the ownership side effect ordered with synchronous termination.
            onAdmission()
            return true
        }
        guard admitted else { return false }

        do {
            try operation()
        } catch {
            clearStart(context: context, capture: capture)
            throw error
        }

        let accepted = lock.withLock { () -> Bool in
            if !isTerminationRequested(),
               reservation?.attemptID == context.attemptID,
               reservation?.generation == context.generation,
               activeCapture?.attemptID == context.attemptID,
               activeCapture?.capture === capture {
                return true
            }
            guard activeCapture?.attemptID == context.attemptID,
                  activeCapture?.capture === capture else {
                return false
            }
            activeCapture = nil
            if reservation?.attemptID == context.attemptID,
               reservation?.generation == context.generation {
                reservation = nil
            }
            // Keep ownership claimed under the slot lock until teardown has actually completed.
            capture.shutdownAndDiscardSynchronously()
            return false
        }
        return accepted
    }

    private func clearStart(
        context: StartContext,
        capture: any VoiceInputAudioCapturing
    ) {
        lock.withLock {
            if activeCapture?.attemptID == context.attemptID,
               activeCapture?.capture === capture {
                activeCapture = nil
            }
            if reservation?.attemptID == context.attemptID,
               reservation?.generation == context.generation {
                reservation = nil
            }
        }
    }

    func clearReservation(attemptID: UUID, generation: UInt64) {
        lock.withLock {
            guard reservation?.attemptID == attemptID,
                  reservation?.generation == generation,
                  activeCapture == nil else {
                return
            }
            reservation = nil
        }
    }

    func clear(_ capture: any VoiceInputAudioCapturing) {
        lock.withLock {
            guard let current = activeCapture, current.capture === capture else { return }
            activeCapture = nil
            reservation = nil
        }
    }

    func shutdownSynchronously(for session: VoiceInputRecognitionSession) {
        lock.withLock {
            guard let activeCapture, activeCapture.session == session else { return }
            activeCapture.capture.shutdownSynchronously()
        }
    }

    func cancelSynchronously(for session: VoiceInputRecognitionSession) {
        lock.withLock {
            guard let activeCapture, activeCapture.session == session else { return }
            guard activeCapture.finalizationGate.requestCancellation() else { return }
            activeCapture.capture.shutdownAndDiscardSynchronously()
        }
    }

    func cancelStartupSynchronously(attemptID: UUID) {
        lock.withLock {
            guard reservation?.attemptID == attemptID else { return }
            reservation = nil
            guard let activeCapture, activeCapture.attemptID == attemptID else { return }
            _ = activeCapture.finalizationGate.requestCancellation()
            self.activeCapture = nil
            activeCapture.capture.shutdownAndDiscardSynchronously()
        }
    }

    func terminateSynchronously() {
        terminationLock.withLock {
            terminationRequested = true
        }
        lock.withLock {
            reservation = nil
            guard let activeCapture else { return }
            self.activeCapture = nil
            _ = activeCapture.finalizationGate.requestCancellation()
            activeCapture.capture.shutdownAndDiscardSynchronously()
        }
    }

    private func isTerminationRequested() -> Bool {
        terminationLock.withLock { terminationRequested }
    }
}

final class VoiceInputSuddenTerminationLease: @unchecked Sendable {
    private let lock = NSLock()
    private let controller: any VoiceInputSuddenTerminationControlling
    private var active = false

    init(controller: any VoiceInputSuddenTerminationControlling) {
        self.controller = controller
    }

    func acquire() {
        // Keep the state transition and ProcessInfo side effect ordered against a concurrent release.
        lock.withLock {
            guard !active else { return }
            active = true
            controller.disable()
        }
    }

    func release() {
        lock.withLock {
            guard active else { return }
            active = false
            controller.enable()
        }
    }
}
