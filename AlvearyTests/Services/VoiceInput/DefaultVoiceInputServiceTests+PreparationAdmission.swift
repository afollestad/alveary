import XCTest

@testable import Alveary

@MainActor
extension DefaultVoiceInputServiceTests {
    func testPreparationWithoutAdmissionIsRejectedBeforeModelWork() async {
        let repository = VoiceInputModelRepositoryFake()
        let service = makeVoiceInputService(repository: repository)

        do {
            _ = try await service.prepare { _ in }
            XCTFail("Expected preparation without admission to be rejected")
        } catch {
            XCTAssertEqual(error as? VoiceInputServiceError, .modelPreparationBusy)
        }

        let prepareCallCount = await repository.preparationModes.count
        XCTAssertEqual(prepareCallCount, 0)
        XCTAssertEqual(service.admitPreparation(), .initiated)
    }

    func testPreparationAdmissionBecomesReadyAndClearsAfterUnload() async throws {
        let service = makeVoiceInputService()

        XCTAssertEqual(service.admitPreparation(), .initiated)
        let result = try await service.prepare { _ in }
        XCTAssertEqual(result.source, .validatedCache)
        XCTAssertFalse(result.requestedMicrophonePermission)
        XCTAssertEqual(service.admitPreparation(), .ready)

        await service.unloadIfIdle()

        XCTAssertEqual(service.admitPreparation(), .initiated)
    }

    func testRequiredPreparationCanBeAdmittedWhileModelIsReady() async throws {
        let repository = VoiceInputModelRepositoryFake()
        let service = makeVoiceInputService(repository: repository)
        try await prepareAdmittedVoiceInputService(service)

        XCTAssertEqual(service.admitPreparation(), .ready)
        XCTAssertEqual(service.admitPreparation(requiringPreparation: true), .initiated)
        XCTAssertEqual(service.admitPreparation(), .busy)
        let result = try await service.prepare { _ in }

        let prepareCallCount = await repository.preparationModes.count
        XCTAssertEqual(prepareCallCount, 1)
        XCTAssertEqual(result.source, .inMemory)
        XCTAssertFalse(result.requestedMicrophonePermission)
        XCTAssertEqual(service.admitPreparation(), .ready)
    }

    func testDownloadedPreparationSourceIsReturnedAuthoritatively() async throws {
        let repository = VoiceInputModelRepositoryFake(
            preparedModel: makeVoiceInputPreparedModel(source: .downloaded(.installation))
        )
        let service = makeVoiceInputService(repository: repository)

        let result = try await prepareAdmittedVoiceInputService(service)

        XCTAssertEqual(result.source, .downloaded(.installation))
        XCTAssertFalse(result.requestedMicrophonePermission)
    }

    func testDownloadedUpdatePreparationSourceIsReturnedAuthoritatively() async throws {
        let repository = VoiceInputModelRepositoryFake(
            preparedModel: makeVoiceInputPreparedModel(source: .downloaded(.update))
        )
        let service = makeVoiceInputService(repository: repository)

        let result = try await prepareAdmittedVoiceInputService(service)

        XCTAssertEqual(result.source, .downloaded(.update))
        XCTAssertFalse(result.requestedMicrophonePermission)
    }

    func testConcurrentPreparationAdmissionRejectsSecondCallerWithoutAnotherModelLoad() async throws {
        let repository = AdmissionSuspendingVoiceModelRepository()
        let service = DefaultVoiceInputService(
            permissionProvider: VoiceInputPermissionFake(status: .authorized),
            modelRepository: repository,
            inferenceEngine: VoiceInputInferenceFake(),
            audioCaptureFactory: { VoiceInputAudioCaptureFake() },
            suddenTerminationController: SuddenTerminationControllerFake(),
            memoryPressureMonitor: MemoryPressureMonitorFake(),
            architectureCheck: { true }
        )

        XCTAssertEqual(service.admitPreparation(), .initiated)
        let first = Task { try await service.prepare { _ in } }
        await waitForPendingPreparation(repository)

        XCTAssertEqual(service.admitPreparation(), .busy)
        do {
            _ = try await service.prepare { _ in }
            XCTFail("Expected the defensive second preparation to be rejected")
        } catch {
            XCTAssertEqual(error as? VoiceInputServiceError, .modelPreparationBusy)
        }
        await repository.resumePreparation()
        _ = try await first.value

        let prepareCallCount = await repository.prepareCallCount
        XCTAssertEqual(prepareCallCount, 1)
        XCTAssertEqual(service.admitPreparation(), .ready)
    }

    func testFailedPreparationAllowsFreshActivationToRetry() async throws {
        let repository = AdmissionSuspendingVoiceModelRepository()
        let service = makeVoiceInputService(repository: repository)

        XCTAssertEqual(service.admitPreparation(), .initiated)
        let first = Task { try await service.prepare { _ in } }
        await waitForPendingPreparation(repository)

        XCTAssertEqual(service.admitPreparation(), .busy)
        await repository.resumePreparation(error: .modelDownload("offline"))

        let firstError = await preparationError(from: first)
        XCTAssertEqual(firstError, .modelDownload("offline"))
        let failedPrepareCallCount = await repository.prepareCallCount
        XCTAssertEqual(failedPrepareCallCount, 1)

        XCTAssertEqual(service.admitPreparation(), .initiated)
        let retry = Task { try await service.prepare { _ in } }
        await waitForPendingPreparation(repository)
        await repository.resumePreparation()
        _ = try await retry.value

        let finalPrepareCallCount = await repository.prepareCallCount
        XCTAssertEqual(finalPrepareCallCount, 2)
        XCTAssertEqual(service.admitPreparation(), .ready)
    }

    func testCancelledPreparationStaysBusyUntilOwningOperationReturnsThenAllowsRetry() async throws {
        let repository = AdmissionSuspendingVoiceModelRepository()
        let service = makeVoiceInputService(repository: repository)

        XCTAssertEqual(service.admitPreparation(), .initiated)
        let first = Task { try await service.prepare { _ in } }
        await waitForPendingPreparation(repository)
        first.cancel()

        XCTAssertEqual(service.admitPreparation(), .busy)
        do {
            _ = try await service.prepare { _ in }
            XCTFail("Expected preparation to remain busy until the owning operation returns")
        } catch {
            XCTAssertEqual(error as? VoiceInputServiceError, .modelPreparationBusy)
        }

        await repository.resumePreparation()
        do {
            _ = try await first.value
            XCTFail("Expected the owning preparation to observe cancellation")
        } catch is CancellationError {
            // Expected after the non-cooperative repository operation returns.
        }

        XCTAssertEqual(service.admitPreparation(), .initiated)
        let retry = Task { try await service.prepare { _ in } }
        await waitForPendingPreparation(repository)
        await repository.resumePreparation()
        _ = try await retry.value

        let prepareCallCount = await repository.prepareCallCount
        XCTAssertEqual(prepareCallCount, 2)
        XCTAssertEqual(service.admitPreparation(), .ready)
    }

    func testFailedPreparationReleasesAdmission() async {
        let repository = VoiceInputModelRepositoryFake()
        await repository.setPrepareErrors([.modelDownload("offline")])
        let service = makeVoiceInputService(repository: repository)

        XCTAssertEqual(service.admitPreparation(), .initiated)
        do {
            _ = try await service.prepare { _ in }
            XCTFail("Expected preparation failure")
        } catch {
            XCTAssertEqual(error as? VoiceInputServiceError, .modelDownload("offline"))
        }

        XCTAssertEqual(service.admitPreparation(), .initiated)
    }

    func testUnhealthyResetInvalidatesReadiness() async throws {
        let inference = VoiceInputInferenceFake()
        let service = makeVoiceInputService(inference: inference)
        XCTAssertEqual(service.admitPreparation(), .initiated)
        _ = try await service.prepare { _ in }
        XCTAssertEqual(service.admitPreparation(), .ready)
        await inference.setResetError(VoiceInputInferenceFakeError(message: "reset failed"))

        do {
            _ = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
            XCTFail("Expected reset failure")
        } catch {
            XCTAssertEqual(error as? VoiceInputServiceError, .inference("reset failed"))
        }

        XCTAssertEqual(service.admitPreparation(), .initiated)
    }

    private func waitForPendingPreparation(_ repository: AdmissionSuspendingVoiceModelRepository) async {
        for _ in 0..<500 {
            if await repository.hasPendingPreparation {
                return
            }
            await Task.yield()
        }
        XCTFail("Expected model preparation to suspend")
    }

    private func preparationError(
        from task: Task<VoiceInputPreparationResult, Error>
    ) async -> VoiceInputServiceError? {
        do {
            _ = try await task.value
            XCTFail("Expected model preparation to fail")
            return nil
        } catch {
            return error as? VoiceInputServiceError
        }
    }
}

private actor AdmissionSuspendingVoiceModelRepository: VoiceInputModelRepository {
    private var continuation: CheckedContinuation<Void, Never>?
    private var pendingError: VoiceInputServiceError?
    private(set) var prepareCallCount = 0

    var hasPendingPreparation: Bool {
        continuation != nil
    }

    func prepareModel(
        mode: VoiceInputModelPreparationMode,
        progress: @escaping VoiceInputPreparationProgressHandler
    ) async throws -> VoiceInputPreparedModel {
        prepareCallCount += 1
        progress(.checkingModel)
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        if let pendingError {
            self.pendingError = nil
            throw pendingError
        }
        return makeVoiceInputPreparedModel()
    }

    func purgeValidatedModel() async throws {}

    func resumePreparation(error: VoiceInputServiceError? = nil) {
        pendingError = error
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}

private extension VoiceInputModelRepositoryFake {
    func setPrepareErrors(_ errors: [VoiceInputServiceError]) {
        prepareErrors = errors
    }
}
