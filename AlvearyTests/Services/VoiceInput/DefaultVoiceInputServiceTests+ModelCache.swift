@testable import Alveary
import Foundation
import XCTest

@MainActor
extension DefaultVoiceInputServiceTests {
    func testClearModelCacheCleansInferenceBeforeDeletingFilesAndResetsReadiness() async throws {
        let inference = VoiceInputInferenceFake()
        let repository = CacheClearVoiceInputModelRepositoryFake(inference: inference)
        let service = makeCacheClearService(repository: repository, inference: inference)
        try await prepareAdmittedVoiceInputService(service)

        try await service.clearModelCache()

        let operationsAtPurge = await repository.inferenceOperationsAtPurge
        let purgeCount = await repository.purgeAllCount
        XCTAssertTrue(operationsAtPurge.contains("cleanup"))
        XCTAssertEqual(purgeCount, 1)
        XCTAssertEqual(service.admitPreparation(), .initiated)
    }

    func testClearModelCacheRefusesActiveRecognitionWithoutDeletingFiles() async throws {
        let inference = VoiceInputInferenceFake()
        let repository = CacheClearVoiceInputModelRepositoryFake(inference: inference)
        let capture = VoiceInputAudioCaptureFake()
        let service = makeCacheClearService(repository: repository, inference: inference, capture: capture)
        try await prepareAdmittedVoiceInputService(service)
        let session = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }

        do {
            try await service.clearModelCache()
            XCTFail("Expected active-recognition rejection")
        } catch let error as VoiceInputServiceError {
            XCTAssertEqual(error, .modelCacheBusy)
        }

        let purgeCount = await repository.purgeAllCount
        XCTAssertEqual(purgeCount, 0)
        await service.cancelRecognition(session)
    }

    func testClearModelCacheRefusesPreparationInProgress() async throws {
        let inference = VoiceInputInferenceFake()
        let repository = CacheClearVoiceInputModelRepositoryFake(
            inference: inference,
            suspendsPreparation: true
        )
        let service = makeCacheClearService(repository: repository, inference: inference)
        let preparation = Task {
            try await prepareAdmittedVoiceInputService(service)
        }
        await waitForCacheClearPreparation(repository)

        do {
            try await service.clearModelCache()
            XCTFail("Expected preparation rejection")
        } catch let error as VoiceInputServiceError {
            XCTAssertEqual(error, .modelCacheBusy)
        }

        let purgeCount = await repository.purgeAllCount
        XCTAssertEqual(purgeCount, 0)
        await repository.resumePreparation()
        _ = try await preparation.value
    }

    func testUnpinnedModelsAreRemovedOnlyAfterIdleInferenceCleanup() async throws {
        let inference = VoiceInputInferenceFake()
        let repository = DeferredModelCleanupRepositoryFake(inference: inference)
        let service = DefaultVoiceInputService(
            permissionProvider: VoiceInputPermissionFake(status: .authorized),
            modelRepository: repository,
            inferenceEngine: inference,
            audioCaptureFactory: { VoiceInputAudioCaptureFake() },
            suddenTerminationController: SuddenTerminationControllerFake(),
            memoryPressureMonitor: MemoryPressureMonitorFake(),
            architectureCheck: { true }
        )

        try await prepareAdmittedVoiceInputService(service)

        let removalCountAfterPreparation = await repository.removeUnpinnedCount
        XCTAssertEqual(removalCountAfterPreparation, 0)

        await service.unloadIfIdle()

        let operationsAtRemoval = await repository.inferenceOperationsAtRemoval
        let removalCountAfterUnload = await repository.removeUnpinnedCount
        XCTAssertEqual(removalCountAfterUnload, 1)
        XCTAssertEqual(operationsAtRemoval, ["load", "cleanup"])
    }

    func testSuspendedIdleCleanupPublishesNotReadyUntilReloadCompletes() async throws {
        let inference = IdleCleanupInferenceFake()
        let service = makeVoiceInputService(inference: inference)
        try await prepareAdmittedVoiceInputService(service)

        let unload = Task { await service.unloadIfIdle() }
        await waitForPendingIdleCleanup(inference)

        XCTAssertEqual(service.admitPreparation(), .initiated)
        let reload = Task { try await service.prepare { _ in } }
        await inference.resumeCleanup()
        await unload.value
        _ = try await reload.value

        XCTAssertEqual(service.admitPreparation(), .ready)
    }

    func testMemoryPressureDuringRecognitionUnloadsModelAfterRecognitionBecomesIdle() async throws {
        let inference = VoiceInputInferenceFake()
        let memoryPressure = MemoryPressureMonitorFake()
        let service = makeVoiceInputService(inference: inference, memoryPressure: memoryPressure)
        try await prepareAdmittedVoiceInputService(service)
        let session = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }

        memoryPressure.trigger()
        for _ in 0..<50 {
            await Task.yield()
        }
        _ = await service.stopRecognition(session)
        await waitForInferenceCleanup(inference)

        XCTAssertEqual(service.admitPreparation(), .initiated)
    }

    func testDeferredMemoryPressureDoesNotUnloadNewerReadyGeneration() async throws {
        let inference = SuspendingResetVoiceInputInferenceFake()
        let service = makeVoiceInputService(inference: inference)
        try await prepareAdmittedVoiceInputService(service)
        let staleGeneration = try XCTUnwrap(
            service.preparationBroadcast.readyModelGenerationForMemoryPressure()
        )

        let recognition = Task {
            try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
        }
        for _ in 0..<500 {
            if await inference.hasPendingReset {
                break
            }
            await Task.yield()
        }
        let resetIsPending = await inference.hasPendingReset
        XCTAssertTrue(resetIsPending)

        let deferredUnload = Task {
            await service.handleDeferredMemoryPressure(observedModelGeneration: staleGeneration)
        }
        for _ in 0..<50 {
            await Task.yield()
        }

        await inference.resumeReset()
        let session = try await recognition.value
        await deferredUnload.value
        await service.cancelRecognition(session)
        for _ in 0..<50 {
            await Task.yield()
        }

        let cleanupCount = await inference.cleanupCount
        XCTAssertEqual(cleanupCount, 0)
        XCTAssertEqual(service.admitPreparation(), .ready)
    }

    private func makeCacheClearService(
        repository: CacheClearVoiceInputModelRepositoryFake,
        inference: VoiceInputInferenceFake,
        capture: VoiceInputAudioCaptureFake = VoiceInputAudioCaptureFake()
    ) -> DefaultVoiceInputService {
        DefaultVoiceInputService(
            permissionProvider: VoiceInputPermissionFake(status: .authorized),
            modelRepository: repository,
            inferenceEngine: inference,
            audioCaptureFactory: { capture },
            suddenTerminationController: SuddenTerminationControllerFake(),
            memoryPressureMonitor: MemoryPressureMonitorFake(),
            architectureCheck: { true }
        )
    }

    private func waitForCacheClearPreparation(_ repository: CacheClearVoiceInputModelRepositoryFake) async {
        for _ in 0..<500 {
            if await repository.hasPendingPreparation {
                return
            }
            await Task.yield()
        }
        XCTFail("Expected model preparation to suspend")
    }

    private func waitForPendingIdleCleanup(_ inference: IdleCleanupInferenceFake) async {
        for _ in 0..<500 {
            if await inference.hasPendingCleanup {
                return
            }
            await Task.yield()
        }
        XCTFail("Expected idle inference cleanup to suspend")
    }

    private func waitForInferenceCleanup(_ inference: VoiceInputInferenceFake) async {
        for _ in 0..<500 {
            let operations = await inference.operations
            if operations.contains("cleanup") {
                return
            }
            await Task.yield()
        }
        XCTFail("Expected deferred memory-pressure cleanup")
    }
}

private actor CacheClearVoiceInputModelRepositoryFake: VoiceInputModelRepository {
    private let inference: VoiceInputInferenceFake
    private let suspendsPreparation: Bool
    private var preparationContinuation: CheckedContinuation<Void, Never>?
    private(set) var inferenceOperationsAtPurge: [String] = []
    private(set) var purgeAllCount = 0

    init(inference: VoiceInputInferenceFake, suspendsPreparation: Bool = false) {
        self.inference = inference
        self.suspendsPreparation = suspendsPreparation
    }

    var hasPendingPreparation: Bool {
        preparationContinuation != nil
    }

    func prepareModel(
        mode: VoiceInputModelPreparationMode,
        progress: @escaping VoiceInputPreparationProgressHandler
    ) async throws -> VoiceInputPreparedModel {
        progress(.checkingModel)
        if suspendsPreparation {
            await withCheckedContinuation { continuation in
                preparationContinuation = continuation
            }
        }
        return makeVoiceInputPreparedModel()
    }

    func purgeValidatedModel() async throws {}
    func removeUnpinnedModels() async throws {}

    func purgeAllModels() async throws {
        inferenceOperationsAtPurge = await inference.operations
        purgeAllCount += 1
    }

    func resumePreparation() {
        let continuation = preparationContinuation
        preparationContinuation = nil
        continuation?.resume()
    }
}

private actor DeferredModelCleanupRepositoryFake: VoiceInputModelRepository {
    private let inference: VoiceInputInferenceFake
    private(set) var inferenceOperationsAtRemoval: [String] = []
    private(set) var removeUnpinnedCount = 0

    init(inference: VoiceInputInferenceFake) {
        self.inference = inference
    }

    func prepareModel(
        mode: VoiceInputModelPreparationMode,
        progress: @escaping VoiceInputPreparationProgressHandler
    ) async throws -> VoiceInputPreparedModel {
        makeVoiceInputPreparedModel()
    }

    func purgeValidatedModel() async throws {}
    func purgeAllModels() async throws {}

    func removeUnpinnedModels() async throws {
        inferenceOperationsAtRemoval = await inference.operations
        removeUnpinnedCount += 1
    }
}

private actor IdleCleanupInferenceFake: VoiceInputInferenceEngine {
    private var cleanupContinuation: CheckedContinuation<Void, Never>?

    var hasPendingCleanup: Bool {
        cleanupContinuation != nil
    }

    func loadModels(from directory: URL) async throws {}
    func reset() async throws {}
    func process(_ buffer: VoiceInputPCMTransfer) async throws -> String { "" }

    func finishAndReset() async throws -> VoiceInputInferenceFinalization {
        VoiceInputInferenceFinalization(transcript: "", isReusable: true)
    }

    func cancelAndReset() async -> Bool { true }

    func cleanup() async {
        await withCheckedContinuation { continuation in
            cleanupContinuation = continuation
        }
    }

    func resumeCleanup() {
        let continuation = cleanupContinuation
        cleanupContinuation = nil
        continuation?.resume()
    }
}
