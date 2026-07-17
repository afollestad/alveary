@testable import Alveary
import AVFoundation
import Foundation

extension VoiceInputModelRepository {
    func removeUnpinnedModels() async throws {}
    func purgeAllModels() async throws {}
}

final class VoiceInputPermissionFake: VoiceInputPermissionProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var status: VoiceInputPermissionStatus
    private let requestResult: Bool
    private(set) var requestCount = 0

    init(status: VoiceInputPermissionStatus, requestResult: Bool = true) {
        self.status = status
        self.requestResult = requestResult
    }

    func authorizationStatus() -> VoiceInputPermissionStatus {
        lock.withLock { status }
    }

    func requestAccess() async -> Bool {
        lock.withLock {
            requestCount += 1
            if requestResult {
                status = .authorized
            }
        }
        return requestResult
    }

    func setStatus(_ status: VoiceInputPermissionStatus) {
        lock.withLock {
            self.status = status
        }
    }
}

actor VoiceInputModelRepositoryFake: VoiceInputModelRepository {
    var preparedModel: VoiceInputPreparedModel
    var prepareErrors: [VoiceInputServiceError] = []
    private(set) var preparationModes: [VoiceInputModelPreparationMode] = []
    private(set) var purgeCount = 0
    private(set) var removeUnpinnedCount = 0
    private(set) var purgeAllCount = 0

    init(preparedModel: VoiceInputPreparedModel = makeVoiceInputPreparedModel()) {
        self.preparedModel = preparedModel
    }

    func prepareModel(
        mode: VoiceInputModelPreparationMode,
        progress: @escaping VoiceInputPreparationProgressHandler
    ) async throws -> VoiceInputPreparedModel {
        preparationModes.append(mode)
        progress(.checkingModel)
        if !prepareErrors.isEmpty {
            throw prepareErrors.removeFirst()
        }
        return preparedModel
    }

    func purgeValidatedModel() async throws {
        purgeCount += 1
    }

    func removeUnpinnedModels() async throws {
        removeUnpinnedCount += 1
    }

    func purgeAllModels() async throws {
        purgeAllCount += 1
    }
}

actor VoiceInputInferenceFake: VoiceInputInferenceEngine {
    var loadErrors: [VoiceInputServiceError] = []
    var processOutputs: [String] = []
    var processErrors: [VoiceInputServiceError] = []
    var finalOutput = ""
    var finalError: VoiceInputInferenceFakeError?
    var finalizationIsReusable = true
    var failureResetIsReusable = true
    var cancelAndResetIsReusable = true
    var resetError: VoiceInputInferenceFakeError?
    private(set) var operations: [String] = []

    func loadModels(from directory: URL) async throws {
        operations.append("load")
        if !loadErrors.isEmpty {
            throw loadErrors.removeFirst()
        }
    }

    func reset() async throws {
        operations.append("reset")
        if let resetError {
            self.resetError = nil
            throw resetError
        }
    }

    func process(_ buffer: VoiceInputPCMTransfer) async throws -> String {
        operations.append("process")
        if !processErrors.isEmpty {
            throw processErrors.removeFirst()
        }
        return processOutputs.isEmpty ? "" : processOutputs.removeFirst()
    }

    func finishAndReset() async throws -> VoiceInputInferenceFinalization {
        operations.append("finish")
        if let finalError {
            throw VoiceInputInferenceOperationError(
                message: finalError.localizedDescription,
                isReusable: failureResetIsReusable
            )
        }
        return VoiceInputInferenceFinalization(
            transcript: finalOutput,
            isReusable: finalizationIsReusable
        )
    }

    func cancelAndReset() async -> Bool {
        operations.append("cancel")
        return cancelAndResetIsReusable
    }

    func cleanup() async {
        operations.append("cleanup")
    }
}

struct VoiceInputInferenceFakeError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}

actor SuspendingResetVoiceInputInferenceFake: VoiceInputInferenceEngine {
    private var resetContinuation: CheckedContinuation<Void, Never>?
    private(set) var cleanupCount = 0

    var hasPendingReset: Bool {
        resetContinuation != nil
    }

    func loadModels(from directory: URL) async throws {}

    func reset() async throws {
        await withCheckedContinuation { continuation in
            resetContinuation = continuation
        }
    }

    func resumeReset() {
        let continuation = resetContinuation
        resetContinuation = nil
        continuation?.resume()
    }

    func process(_ buffer: VoiceInputPCMTransfer) async throws -> String { "" }
    func finishAndReset() async throws -> VoiceInputInferenceFinalization {
        VoiceInputInferenceFinalization(transcript: "", isReusable: true)
    }
    func cancelAndReset() async -> Bool { true }
    func cleanup() async {
        cleanupCount += 1
    }
}

final class VoiceInputAudioCaptureFake: VoiceInputAudioCapturing, @unchecked Sendable {
    private let lock = NSLock()
    private let startCondition = NSCondition()
    private var consumer: (@Sendable (VoiceInputCaptureEvent) async -> Void)?
    private(set) var startCount = 0
    private(set) var synchronousShutdownCount = 0
    private(set) var synchronousDiscardCount = 0
    private(set) var drainCount = 0
    private(set) var discardCount = 0
    var startError: VoiceInputServiceError?
    private var suspendsDrain = false
    private var pendingDrain: CheckedContinuation<Void, Never>?
    private var suspendsDiscard = false
    private var pendingDiscard: CheckedContinuation<Void, Never>?
    private var suspendsStart = false
    private var pendingStart = false
    private var isSynchronouslyClosed = false

    var hasPendingStart: Bool {
        startCondition.withLock { pendingStart }
    }

    var hasPendingDrain: Bool {
        lock.withLock { pendingDrain != nil }
    }

    var hasPendingDiscard: Bool {
        lock.withLock { pendingDiscard != nil }
    }

    func start(
        generation: UInt64,
        consumer: @escaping @Sendable (VoiceInputCaptureEvent) async -> Void
    ) throws {
        if let startError { throw startError }
        lock.withLock {
            startCount += 1
            self.consumer = consumer
        }
        startCondition.lock()
        if isSynchronouslyClosed {
            startCondition.unlock()
            throw VoiceInputServiceError.recognitionSessionExpired
        }
        pendingStart = suspendsStart
        while suspendsStart, !isSynchronouslyClosed {
            startCondition.wait()
        }
        pendingStart = false
        let wasClosed = isSynchronouslyClosed
        startCondition.unlock()
        if wasClosed {
            throw VoiceInputServiceError.recognitionSessionExpired
        }
    }

    func stopAndDrain() async {
        let shouldSuspend = lock.withLock { () -> Bool in
            drainCount += 1
            return suspendsDrain
        }
        guard shouldSuspend else { return }
        await withCheckedContinuation { continuation in
            lock.withLock {
                pendingDrain = continuation
            }
        }
    }

    func stopAndDiscard() async {
        let shouldSuspend = lock.withLock { () -> Bool in
            discardCount += 1
            return suspendsDiscard
        }
        guard shouldSuspend else { return }
        await withCheckedContinuation { continuation in
            lock.withLock {
                pendingDiscard = continuation
            }
        }
    }

    func shutdownSynchronously() {
        guard closeSynchronously() else { return }
        lock.withLock {
            synchronousShutdownCount += 1
        }
    }

    func shutdownAndDiscardSynchronously() {
        guard closeSynchronously() else { return }
        lock.withLock {
            synchronousDiscardCount += 1
        }
    }

    private func closeSynchronously() -> Bool {
        startCondition.withLock {
            guard !isSynchronouslyClosed else { return false }
            if pendingStart {
                isSynchronouslyClosed = true
            }
            return true
        }
    }

    func setSuspendsDrain(_ value: Bool) {
        lock.withLock {
            suspendsDrain = value
        }
    }

    func setSuspendsStart(_ value: Bool) {
        startCondition.withLock {
            suspendsStart = value
        }
    }

    func resumePendingStart() {
        startCondition.withLock {
            suspendsStart = false
            startCondition.broadcast()
        }
    }

    func resumePendingDrain() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { pendingDrain = nil }
            suspendsDrain = false
            return pendingDrain
        }
        continuation?.resume()
    }

    func setSuspendsDiscard(_ value: Bool) {
        lock.withLock {
            suspendsDiscard = value
        }
    }

    func resumePendingDiscard() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { pendingDiscard = nil }
            suspendsDiscard = false
            return pendingDiscard
        }
        continuation?.resume()
    }

    func emit(_ event: VoiceInputCaptureEvent) async {
        let consumer = lock.withLock { self.consumer }
        await consumer?(event)
    }
}

final class VoiceInputCaptureFactoryFake: @unchecked Sendable {
    private let lock = NSLock()
    private var captures: [VoiceInputAudioCaptureFake]

    init(captures: [VoiceInputAudioCaptureFake]) {
        self.captures = captures
    }

    func makeCapture() -> any VoiceInputAudioCapturing {
        lock.withLock {
            precondition(!captures.isEmpty)
            return captures.removeFirst()
        }
    }
}

final class SuddenTerminationControllerFake: VoiceInputSuddenTerminationControlling, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var disableCount = 0
    private(set) var enableCount = 0

    func disable() {
        lock.withLock { disableCount += 1 }
    }

    func enable() {
        lock.withLock { enableCount += 1 }
    }
}

final class MemoryPressureMonitorFake: VoiceInputMemoryPressureMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(handler: @escaping @Sendable () -> Void) {
        lock.withLock {
            startCount += 1
            self.handler = handler
        }
    }

    func stop() {
        lock.withLock {
            stopCount += 1
            handler = nil
        }
    }

    func trigger() {
        let handler = lock.withLock { self.handler }
        handler?()
    }
}

final class VoiceInputUpdateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [VoiceInputRecognitionUpdate] = []

    var updates: [VoiceInputRecognitionUpdate] {
        lock.withLock { storage }
    }

    func append(_ update: VoiceInputRecognitionUpdate) {
        lock.withLock { storage.append(update) }
    }
}

final class VoiceInputProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [VoiceInputPreparationProgress] = []

    var values: [VoiceInputPreparationProgress] {
        lock.withLock { storage }
    }

    func append(_ progress: VoiceInputPreparationProgress) {
        lock.withLock { storage.append(progress) }
    }
}

func makeVoiceInputPreparedModel(
    directory: URL = URL(fileURLWithPath: "/tmp/voice-model"),
    source: VoiceInputPreparedModel.Source = .validatedCache
) -> VoiceInputPreparedModel {
    VoiceInputPreparedModel(
        repositoryDirectory: directory,
        manifest: VoiceInputModelManifest(
            schema: VoiceInputModelManifest.currentSchema,
            fluidAudioRevision: VoiceInputModelManifest.fluidAudioRevision,
            repository: VoiceInputPinnedModelDescriptor.expectedRepository,
            modelRevision: "4252711f6f060f9a2f91e5f081a806d7f45eebd8",
            descriptorSHA256: String(repeating: "a", count: 64),
            configuration: VoiceInputModelASRConfiguration(
                encoderPrecision: "int8",
                leftFrames: 70,
                chunkFrames: 2,
                rightFrames: 2,
                encoder: "parakeet_unified_encoder_streaming_70_2_2_int8.mlmodelc"
            ),
            artifacts: []
        ),
        source: source
    )
}

func makeVoiceInputPCMTransfer() -> VoiceInputPCMTransfer {
    let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160)!
    buffer.frameLength = 160
    return VoiceInputPCMTransfer(buffer: buffer)
}

func makeVoiceInputService(
    permission: VoiceInputPermissionFake = VoiceInputPermissionFake(status: .authorized),
    repository: any VoiceInputModelRepository = VoiceInputModelRepositoryFake(),
    inference: any VoiceInputInferenceEngine = VoiceInputInferenceFake(),
    capture: VoiceInputAudioCaptureFake = VoiceInputAudioCaptureFake(),
    suddenTermination: SuddenTerminationControllerFake = SuddenTerminationControllerFake(),
    memoryPressure: MemoryPressureMonitorFake = MemoryPressureMonitorFake(),
    supported: Bool = true
) -> DefaultVoiceInputService {
    DefaultVoiceInputService(
        permissionProvider: permission,
        modelRepository: repository,
        inferenceEngine: inference,
        audioCaptureFactory: { capture },
        suddenTerminationController: suddenTermination,
        memoryPressureMonitor: memoryPressure,
        architectureCheck: { supported }
    )
}

@discardableResult
func prepareAdmittedVoiceInputService(
    _ service: DefaultVoiceInputService,
    requiringPreparation: Bool = false,
    progress: @escaping VoiceInputPreparationProgressHandler = { _ in }
) async throws -> VoiceInputPreparationResult {
    guard service.admitPreparation(requiringPreparation: requiringPreparation) == .initiated else {
        throw VoiceInputServiceError.modelPreparationBusy
    }
    return try await service.prepare(progress: progress)
}
