import Foundation
import XCTest

@testable import Alveary

@MainActor
extension DefaultVoiceInputServiceTests {
    func testCancelledModelLoadWaitsForReturnThenCleansWithoutPurgingCache() async {
        let cancellationErrors: [any Error] = [
            CancellationError(),
            URLError(.cancelled),
            CocoaError(.userCancelled),
            NSError(
                domain: "VoiceInputLoadCancellationTests",
                code: 1,
                userInfo: [NSUnderlyingErrorKey: URLError(.cancelled)]
            )
        ]

        for cancellationError in cancellationErrors {
            let repository = VoiceInputModelRepositoryFake()
            let inference = SuspendingLoadVoiceInputInferenceFake()
            let service = DefaultVoiceInputService(
                permissionProvider: VoiceInputPermissionFake(status: .authorized),
                modelRepository: repository,
                inferenceEngine: inference,
                audioCaptureFactory: { VoiceInputAudioCaptureFake() },
                suddenTerminationController: SuddenTerminationControllerFake(),
                memoryPressureMonitor: MemoryPressureMonitorFake(),
                architectureCheck: { true }
            )

            XCTAssertEqual(service.admitPreparation(), .initiated)
            let preparation = Task {
                try await service.prepare { _ in }
            }
            await waitForPendingModelLoad(inference)

            preparation.cancel()
            for _ in 0..<50 {
                await Task.yield()
            }

            let operationsBeforeReturn = await inference.operations
            let purgeCountBeforeReturn = await repository.purgeCount
            XCTAssertEqual(operationsBeforeReturn, [.loadStarted])
            XCTAssertEqual(purgeCountBeforeReturn, 0)

            await inference.resumeLoad(throwing: cancellationError)
            do {
                _ = try await preparation.value
                XCTFail("Expected model loading to be cancelled")
            } catch is CancellationError {
                // Expected after the owning model-load operation returns.
            } catch {
                XCTFail("Expected CancellationError, got \(error)")
            }

            let operationsAfterReturn = await inference.operations
            let purgeCountAfterReturn = await repository.purgeCount
            XCTAssertEqual(operationsAfterReturn, [.loadStarted, .loadReturned, .cleanup])
            XCTAssertEqual(purgeCountAfterReturn, 0)
            XCTAssertEqual(service.admitPreparation(), .initiated)
        }
    }

    func testCancelledModelLoadReturningGenericFailureDoesNotEnterRepair() async {
        let repository = VoiceInputModelRepositoryFake()
        let inference = SuspendingLoadVoiceInputInferenceFake()
        let service = DefaultVoiceInputService(
            permissionProvider: VoiceInputPermissionFake(status: .authorized),
            modelRepository: repository,
            inferenceEngine: inference,
            audioCaptureFactory: { VoiceInputAudioCaptureFake() },
            suddenTerminationController: SuddenTerminationControllerFake(),
            memoryPressureMonitor: MemoryPressureMonitorFake(),
            architectureCheck: { true }
        )

        let preparation = Task {
            try await prepareAdmittedVoiceInputService(service)
        }
        await waitForPendingModelLoad(inference)
        preparation.cancel()

        await inference.resumeLoad(throwing: VoiceInputServiceError.modelLoad("corrupt"))
        do {
            _ = try await preparation.value
            XCTFail("Expected model loading to be cancelled")
        } catch is CancellationError {
            // Cancellation wins once the owning model-load operation returns.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let operations = await inference.operations
        let purgeCount = await repository.purgeCount
        let preparationModes = await repository.preparationModes
        XCTAssertEqual(operations, [.loadStarted, .loadReturned, .cleanup])
        XCTAssertEqual(purgeCount, 0)
        XCTAssertEqual(preparationModes, [.normal])
    }

    func testCancelledRepairLoadDoesNotPurgeValidatedCacheAgain() async {
        let repository = VoiceInputModelRepositoryFake()
        let inference = SuspendingLoadVoiceInputInferenceFake(failsFirstLoadBeforeSuspending: true)
        let service = DefaultVoiceInputService(
            permissionProvider: VoiceInputPermissionFake(status: .authorized),
            modelRepository: repository,
            inferenceEngine: inference,
            audioCaptureFactory: { VoiceInputAudioCaptureFake() },
            suddenTerminationController: SuddenTerminationControllerFake(),
            memoryPressureMonitor: MemoryPressureMonitorFake(),
            architectureCheck: { true }
        )

        let preparation = Task {
            try await prepareAdmittedVoiceInputService(service)
        }
        await waitForPendingModelLoad(inference)
        preparation.cancel()

        let purgeCountBeforeReturn = await repository.purgeCount
        let preparationModes = await repository.preparationModes
        XCTAssertEqual(purgeCountBeforeReturn, 1)
        XCTAssertEqual(preparationModes, [.normal, .repair])

        await inference.resumeLoad(throwing: CocoaError(.userCancelled))
        do {
            _ = try await preparation.value
            XCTFail("Expected repair model loading to be cancelled")
        } catch is CancellationError {
            // Expected after the repair model-load operation returns.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let operations = await inference.operations
        let purgeCountAfterReturn = await repository.purgeCount
        XCTAssertEqual(
            operations,
            [.loadStarted, .loadReturned, .cleanup, .loadStarted, .loadReturned, .cleanup]
        )
        XCTAssertEqual(purgeCountAfterReturn, 1)
    }

    func testCancelledRepairLoadReturningGenericFailureDoesNotPurgeValidatedCacheAgain() async {
        let repository = VoiceInputModelRepositoryFake()
        let inference = SuspendingLoadVoiceInputInferenceFake(failsFirstLoadBeforeSuspending: true)
        let service = DefaultVoiceInputService(
            permissionProvider: VoiceInputPermissionFake(status: .authorized),
            modelRepository: repository,
            inferenceEngine: inference,
            audioCaptureFactory: { VoiceInputAudioCaptureFake() },
            suddenTerminationController: SuddenTerminationControllerFake(),
            memoryPressureMonitor: MemoryPressureMonitorFake(),
            architectureCheck: { true }
        )

        let preparation = Task {
            try await prepareAdmittedVoiceInputService(service)
        }
        await waitForPendingModelLoad(inference)
        preparation.cancel()

        await inference.resumeLoad(throwing: VoiceInputServiceError.modelLoad("corrupt repair"))
        do {
            _ = try await preparation.value
            XCTFail("Expected repair model loading to be cancelled")
        } catch is CancellationError {
            // Cancellation preserves the repaired validated cache.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let operations = await inference.operations
        let purgeCount = await repository.purgeCount
        let preparationModes = await repository.preparationModes
        XCTAssertEqual(
            operations,
            [.loadStarted, .loadReturned, .cleanup, .loadStarted, .loadReturned, .cleanup]
        )
        XCTAssertEqual(purgeCount, 1)
        XCTAssertEqual(preparationModes, [.normal, .repair])
    }

    func testCancellationAfterNoncooperativeSuccessfulLoadCleansBeforeReturning() async {
        let repository = VoiceInputModelRepositoryFake()
        let inference = SuspendingLoadVoiceInputInferenceFake()
        let service = DefaultVoiceInputService(
            permissionProvider: VoiceInputPermissionFake(status: .authorized),
            modelRepository: repository,
            inferenceEngine: inference,
            audioCaptureFactory: { VoiceInputAudioCaptureFake() },
            suddenTerminationController: SuddenTerminationControllerFake(),
            memoryPressureMonitor: MemoryPressureMonitorFake(),
            architectureCheck: { true }
        )

        let preparation = Task {
            try await prepareAdmittedVoiceInputService(service)
        }
        await waitForPendingModelLoad(inference)
        preparation.cancel()

        await inference.resumeLoadSuccessfully()
        do {
            _ = try await preparation.value
            XCTFail("Expected preparation to remain cancelled after model loading returned")
        } catch is CancellationError {
            // Expected after cleaning up the successfully loaded model.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let operations = await inference.operations
        XCTAssertEqual(operations, [.loadStarted, .loadReturned, .cleanup])
        XCTAssertEqual(service.admitPreparation(), .initiated)
    }

    func testMemoryPressureDuringInitialLoadDoesNotInvalidateNewlyReadyModel() async throws {
        let inference = SuspendingLoadVoiceInputInferenceFake()
        let memoryPressure = MemoryPressureMonitorFake()
        let service = DefaultVoiceInputService(
            permissionProvider: VoiceInputPermissionFake(status: .authorized),
            modelRepository: VoiceInputModelRepositoryFake(),
            inferenceEngine: inference,
            audioCaptureFactory: { VoiceInputAudioCaptureFake() },
            suddenTerminationController: SuddenTerminationControllerFake(),
            memoryPressureMonitor: memoryPressure,
            architectureCheck: { true }
        )

        let preparation = Task {
            try await prepareAdmittedVoiceInputService(service)
        }
        await waitForPendingModelLoad(inference)

        XCTAssertEqual(memoryPressure.startCount, 0)
        memoryPressure.trigger()
        for _ in 0..<50 {
            await Task.yield()
        }
        await inference.resumeLoadSuccessfully()
        _ = try await preparation.value
        XCTAssertEqual(memoryPressure.startCount, 1)
        for _ in 0..<50 {
            await Task.yield()
        }

        XCTAssertEqual(service.admitPreparation(), .ready)
        let session = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
        await service.cancelRecognition(session)
        let operations = await inference.operations
        XCTAssertEqual(operations, [.loadStarted, .loadReturned])
    }

    private func waitForPendingModelLoad(_ inference: SuspendingLoadVoiceInputInferenceFake) async {
        for _ in 0..<500 {
            if await inference.hasPendingLoad {
                return
            }
            await Task.yield()
        }
        XCTFail("Expected model loading to suspend")
    }
}

private actor SuspendingLoadVoiceInputInferenceFake: VoiceInputInferenceEngine {
    enum Operation: Equatable {
        case loadStarted
        case loadReturned
        case cleanup
    }

    private var loadContinuation: CheckedContinuation<Void, any Error>?
    private(set) var operations: [Operation] = []
    private let failsFirstLoadBeforeSuspending: Bool
    private var loadCount = 0

    init(failsFirstLoadBeforeSuspending: Bool = false) {
        self.failsFirstLoadBeforeSuspending = failsFirstLoadBeforeSuspending
    }

    var hasPendingLoad: Bool {
        loadContinuation != nil
    }

    func loadModels(from directory: URL) async throws {
        operations.append(.loadStarted)
        loadCount += 1
        if failsFirstLoadBeforeSuspending, loadCount == 1 {
            operations.append(.loadReturned)
            throw VoiceInputServiceError.modelLoad("corrupt")
        }
        do {
            try await withCheckedThrowingContinuation { continuation in
                loadContinuation = continuation
            }
        } catch {
            operations.append(.loadReturned)
            throw error
        }
        operations.append(.loadReturned)
    }

    func resumeLoad(throwing error: any Error) {
        let continuation = loadContinuation
        loadContinuation = nil
        continuation?.resume(throwing: error)
    }

    func resumeLoadSuccessfully() {
        let continuation = loadContinuation
        loadContinuation = nil
        continuation?.resume()
    }

    func reset() async throws {}
    func process(_ buffer: VoiceInputPCMTransfer) async throws -> String { "" }
    func finishAndReset() async throws -> VoiceInputInferenceFinalization {
        VoiceInputInferenceFinalization(transcript: "", isReusable: true)
    }
    func cancelAndReset() async -> Bool { true }

    func cleanup() async {
        operations.append(.cleanup)
    }
}
