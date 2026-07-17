@testable import Alveary
import XCTest

@MainActor
final class DefaultVoiceInputServiceTests: XCTestCase {
    func testPermissionDenialPreventsModelPreparation() async {
        let permission = VoiceInputPermissionFake(status: .denied)
        let repository = VoiceInputModelRepositoryFake()
        let inference = VoiceInputInferenceFake()
        let service = makeVoiceInputService(permission: permission, repository: repository, inference: inference)

        do {
            try await prepareAdmittedVoiceInputService(service)
            XCTFail("Expected permission denial")
        } catch {
            XCTAssertEqual(error as? VoiceInputServiceError, .permissionDenied)
        }
        let preparationModes = await repository.preparationModes
        let inferenceOperations = await inference.operations
        XCTAssertEqual(preparationModes, [])
        XCTAssertEqual(inferenceOperations, [])
    }

    func testPermissionPromptHappensBeforePreparation() async throws {
        let permission = VoiceInputPermissionFake(status: .notDetermined, requestResult: true)
        let repository = VoiceInputModelRepositoryFake()
        let inference = VoiceInputInferenceFake()
        let service = makeVoiceInputService(permission: permission, repository: repository, inference: inference)

        let result = try await prepareAdmittedVoiceInputService(service)

        XCTAssertEqual(permission.requestCount, 1)
        XCTAssertEqual(result.source, .validatedCache)
        XCTAssertTrue(result.requestedMicrophonePermission)
        let preparationModes = await repository.preparationModes
        let inferenceOperations = await inference.operations
        XCTAssertEqual(preparationModes, [.normal])
        XCTAssertEqual(inferenceOperations, ["load"])
    }

    func testPreparedModelDoesNotBypassRevokedPermissionDuringPreparation() async throws {
        let permission = VoiceInputPermissionFake(status: .authorized)
        let repository = VoiceInputModelRepositoryFake()
        let inference = VoiceInputInferenceFake()
        let service = makeVoiceInputService(permission: permission, repository: repository, inference: inference)
        try await prepareAdmittedVoiceInputService(service)
        permission.setStatus(.denied)

        do {
            try await prepareAdmittedVoiceInputService(service, requiringPreparation: true)
            XCTFail("Expected permission denial")
        } catch {
            XCTAssertEqual(error as? VoiceInputServiceError, .permissionDenied)
        }

        let preparationModes = await repository.preparationModes
        let inferenceOperations = await inference.operations
        XCTAssertEqual(preparationModes, [.normal])
        XCTAssertEqual(inferenceOperations, ["load"])
    }

    func testBeginRecognitionRechecksPermissionBeforeResetOrCapture() async throws {
        let permission = VoiceInputPermissionFake(status: .authorized)
        let inference = VoiceInputInferenceFake()
        let capture = VoiceInputAudioCaptureFake()
        let service = makeVoiceInputService(permission: permission, inference: inference, capture: capture)
        try await prepareAdmittedVoiceInputService(service)
        permission.setStatus(.restricted)

        do {
            _ = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
            XCTFail("Expected restricted permission")
        } catch {
            XCTAssertEqual(error as? VoiceInputServiceError, .permissionRestricted)
        }

        let inferenceOperations = await inference.operations
        XCTAssertEqual(inferenceOperations, ["load"])
        XCTAssertEqual(capture.startCount, 0)
    }

    func testBeginRecognitionNeverRequestsUndeterminedPermissionOrStartsCapture() async throws {
        let permission = VoiceInputPermissionFake(status: .authorized)
        let inference = VoiceInputInferenceFake()
        let capture = VoiceInputAudioCaptureFake()
        let service = makeVoiceInputService(permission: permission, inference: inference, capture: capture)
        try await prepareAdmittedVoiceInputService(service)
        permission.setStatus(.notDetermined)

        do {
            _ = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
            XCTFail("Expected preparation to own the permission prompt")
        } catch {
            XCTAssertEqual(error as? VoiceInputServiceError, .permissionNotDetermined)
        }

        XCTAssertEqual(permission.requestCount, 0)
        XCTAssertEqual(capture.startCount, 0)
        let preparationResult = try await prepareAdmittedVoiceInputService(service, requiringPreparation: true)
        XCTAssertEqual(permission.requestCount, 1)
        XCTAssertEqual(preparationResult.source, .inMemory)
        XCTAssertTrue(preparationResult.requestedMicrophonePermission)

        let session = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
        XCTAssertEqual(capture.startCount, 1)
        await service.cancelRecognition(session)
        let inferenceOperations = await inference.operations
        XCTAssertEqual(inferenceOperations, ["load", "reset", "cancel"])
    }

    func testBeginRecognitionMapsResetFailureAndClearsReservation() async throws {
        let inference = VoiceInputInferenceFake()
        let capture = VoiceInputAudioCaptureFake()
        let service = makeVoiceInputService(inference: inference, capture: capture)
        try await prepareAdmittedVoiceInputService(service)
        await inference.setResetError(VoiceInputInferenceFakeError(message: "reset failed"))

        do {
            _ = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
            XCTFail("Expected reset failure")
        } catch {
            XCTAssertEqual(error as? VoiceInputServiceError, .inference("reset failed"))
        }
        XCTAssertEqual(capture.startCount, 0)

        do {
            _ = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
            XCTFail("Expected reset failure to invalidate the loaded manager")
        } catch {
            XCTAssertEqual(
                error as? VoiceInputServiceError,
                .modelLoad("The voice model has not been prepared.")
            )
        }
        try await prepareAdmittedVoiceInputService(service)
        let session = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
        await service.cancelRecognition(session)
        let inferenceOperations = await inference.operations
        XCTAssertEqual(inferenceOperations, ["load", "reset", "cleanup", "load", "reset", "cancel"])
    }

    func testPrepareReloadsModelAfterMemoryPressureUnloadsItWhileIdle() async throws {
        let permission = VoiceInputPermissionFake(status: .authorized)
        let repository = VoiceInputModelRepositoryFake()
        let inference = VoiceInputInferenceFake()
        let memoryPressure = MemoryPressureMonitorFake()
        let service = makeVoiceInputService(
            permission: permission,
            repository: repository,
            inference: inference,
            memoryPressure: memoryPressure
        )
        try await prepareAdmittedVoiceInputService(service)
        XCTAssertEqual(memoryPressure.startCount, 1)
        memoryPressure.trigger()
        await service.unloadIfIdle()
        permission.setStatus(.notDetermined)

        do {
            _ = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
            XCTFail("Expected the unloaded model to require preparation")
        } catch {
            XCTAssertEqual(
                error as? VoiceInputServiceError,
                .modelLoad("The voice model has not been prepared.")
            )
        }
        XCTAssertEqual(permission.requestCount, 0)

        try await prepareAdmittedVoiceInputService(service)
        let preparationModes = await repository.preparationModes
        let inferenceOperations = await inference.operations
        XCTAssertEqual(permission.requestCount, 1)
        XCTAssertEqual(preparationModes, [.normal, .normal])
        XCTAssertEqual(inferenceOperations, ["load", "cleanup", "load"])
    }

    func testFailedLoadCleansUpPurgesAndRepairsOnce() async throws {
        let repository = VoiceInputModelRepositoryFake()
        let inference = VoiceInputInferenceFake()
        await inference.setLoadErrors([.modelLoad("corrupt")])
        let service = makeVoiceInputService(repository: repository, inference: inference)

        try await prepareAdmittedVoiceInputService(service)

        let preparationModes = await repository.preparationModes
        let purgeCount = await repository.purgeCount
        let inferenceOperations = await inference.operations
        XCTAssertEqual(preparationModes, [.normal, .repair])
        XCTAssertEqual(purgeCount, 1)
        XCTAssertEqual(inferenceOperations, ["load", "cleanup", "load"])
    }

    func testOnlyOneRecognitionLeaseCanBeActive() async throws {
        let service = makeVoiceInputService()
        try await prepareAdmittedVoiceInputService(service)
        let session = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }

        do {
            _ = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
            XCTFail("Expected an active-lease error")
        } catch {
            XCTAssertEqual(error as? VoiceInputServiceError, .alreadyRecording)
        }
        await service.cancelRecognition(session)
    }

    func testFinalTranscriptWinsOverLatestPartial() async throws {
        let inference = VoiceInputInferenceFake()
        await inference.setProcessOutputs(["partial words"])
        await inference.setFinalOutput("final words")
        let capture = VoiceInputAudioCaptureFake()
        let updates = VoiceInputUpdateRecorder()
        let service = makeVoiceInputService(inference: inference, capture: capture)
        try await prepareAdmittedVoiceInputService(service)
        let session = try await service.beginRecognition(
            attempt: VoiceInputRecognitionAttempt(),
            onUpdate: updates.append
        )

        await capture.emit(.audio(makeVoiceInputPCMTransfer()))
        let result = await service.stopRecognition(session)

        XCTAssertEqual(result.transcript, "final words")
        XCTAssertEqual(result.termination, .committed)
        XCTAssertEqual(updates.updates, [.partial(session: session, text: "partial words")])
    }

    func testEmptyFinalFallsBackToLatestNonemptyPartial() async throws {
        let inference = VoiceInputInferenceFake()
        await inference.setProcessOutputs(["latest partial"])
        await inference.setFinalOutput("  \n")
        let capture = VoiceInputAudioCaptureFake()
        let service = makeVoiceInputService(inference: inference, capture: capture)
        try await prepareAdmittedVoiceInputService(service)
        let session = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }

        await capture.emit(.audio(makeVoiceInputPCMTransfer()))
        let result = await service.stopRecognition(session)

        XCTAssertEqual(result.transcript, "latest partial")
    }

    func testCancelSkipsFinishAndBalancesSuddenTermination() async throws {
        let inference = VoiceInputInferenceFake()
        let capture = VoiceInputAudioCaptureFake()
        let suddenTermination = SuddenTerminationControllerFake()
        let service = makeVoiceInputService(
            inference: inference,
            capture: capture,
            suddenTermination: suddenTermination
        )
        try await prepareAdmittedVoiceInputService(service)
        let session = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }

        await service.cancelRecognition(session)

        let inferenceOperations = await inference.operations
        XCTAssertEqual(inferenceOperations, ["load", "reset", "cancel"])
        XCTAssertEqual(capture.synchronousDiscardCount, 1)
        XCTAssertEqual(capture.discardCount, 1)
        XCTAssertEqual(capture.drainCount, 0)
        XCTAssertEqual(suddenTermination.disableCount, 1)
        XCTAssertEqual(suddenTermination.enableCount, 1)
    }

    func testCancelDuringPendingFinalizationDiscardsAndSkipsFinish() async throws {
        let inference = VoiceInputInferenceFake()
        let capture = VoiceInputAudioCaptureFake()
        capture.setSuspendsDrain(true)
        let suddenTermination = SuddenTerminationControllerFake()
        let service = makeVoiceInputService(
            inference: inference,
            capture: capture,
            suddenTermination: suddenTermination
        )
        try await prepareAdmittedVoiceInputService(service)
        let session = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }

        let stopTask = Task { await service.stopRecognition(session) }
        for _ in 0..<500 where !capture.hasPendingDrain {
            await Task.yield()
        }
        XCTAssertTrue(capture.hasPendingDrain)

        service.cancelCaptureSynchronously(for: session)
        let cancelTask = Task { await service.cancelRecognition(session) }
        capture.resumePendingDrain()

        let result = await stopTask.value
        await cancelTask.value
        let inferenceOperations = await inference.operations
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(inferenceOperations, ["load", "reset", "cancel"])
        XCTAssertEqual(capture.synchronousDiscardCount, 1)
        XCTAssertEqual(suddenTermination.disableCount, 1)
        XCTAssertEqual(suddenTermination.enableCount, 1)
    }

    func testCaptureOverflowStopsAndCommitsLatestPartial() async throws {
        let inference = VoiceInputInferenceFake()
        await inference.setProcessOutputs(["usable partial"])
        await inference.setFinalOutput("")
        let capture = VoiceInputAudioCaptureFake()
        let updates = VoiceInputUpdateRecorder()
        let suddenTermination = SuddenTerminationControllerFake()
        let service = makeVoiceInputService(
            inference: inference,
            capture: capture,
            suddenTermination: suddenTermination
        )
        try await prepareAdmittedVoiceInputService(service)
        let session = try await service.beginRecognition(
            attempt: VoiceInputRecognitionAttempt(),
            onUpdate: updates.append
        )
        await capture.emit(.audio(makeVoiceInputPCMTransfer()))

        await capture.emit(.failed(.captureQueueOverflow))
        let result = await service.stopRecognition(session)

        XCTAssertEqual(result.transcript, "usable partial")
        XCTAssertEqual(result.termination, .captureFailure)
        XCTAssertEqual(result.error, .captureQueueOverflow)
        XCTAssertEqual(suddenTermination.disableCount, 1)
        XCTAssertEqual(suddenTermination.enableCount, 1)
        XCTAssertTrue(updates.updates.contains(.captureFailed(session: session, error: .captureQueueOverflow)))
        XCTAssertTrue(updates.updates.contains(.stopped(session: session, result: result)))
    }

    func testCancelledQueuedAttemptDoesNotAffectOwningStartupOrBeginLater() async throws {
        let inference = SuspendingResetVoiceInputInferenceFake()
        let capture = VoiceInputAudioCaptureFake()
        let service = makeVoiceInputService(inference: inference, capture: capture)
        try await prepareAdmittedVoiceInputService(service)

        let owningAttempt = VoiceInputRecognitionAttempt()
        let owningTask = Task {
            try await service.beginRecognition(attempt: owningAttempt) { _ in }
        }
        for _ in 0..<500 {
            if await inference.hasPendingReset {
                break
            }
            await Task.yield()
        }
        let owningResetIsPending = await inference.hasPendingReset
        XCTAssertTrue(owningResetIsPending)

        let queuedAttempt = VoiceInputRecognitionAttempt()
        let queuedTask = Task {
            try await service.beginRecognition(attempt: queuedAttempt) { _ in }
        }
        for _ in 0..<20 {
            await Task.yield()
        }

        queuedAttempt.cancelSynchronously()
        XCTAssertEqual(capture.synchronousDiscardCount, 0)
        await inference.resumeReset()

        let owningSession = try await owningTask.value
        XCTAssertEqual(capture.startCount, 1)
        do {
            _ = try await queuedTask.value
            XCTFail("Expected the queued cancelled attempt to be rejected")
        } catch {
            XCTAssertEqual(error as? VoiceInputServiceError, .recognitionSessionExpired)
        }
        XCTAssertEqual(capture.synchronousDiscardCount, 0)

        await service.cancelRecognition(owningSession)
    }

    func testTerminationLatchRejectsRecognitionThatHasNotEnteredStartup() async throws {
        let inference = VoiceInputInferenceFake()
        let capture = VoiceInputAudioCaptureFake()
        let service = makeVoiceInputService(inference: inference, capture: capture)
        try await prepareAdmittedVoiceInputService(service)

        service.prepareForTerminationSynchronously()

        do {
            _ = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
            XCTFail("Expected termination to close capture admission")
        } catch {
            XCTAssertEqual(error as? VoiceInputServiceError, .recognitionSessionExpired)
        }
        XCTAssertEqual(capture.startCount, 0)
        let operations = await inference.operations
        XCTAssertEqual(operations, ["load"])
    }

    func testUnsupportedArchitectureDoesNoPermissionOrModelWork() async {
        let permission = VoiceInputPermissionFake(status: .notDetermined)
        let repository = VoiceInputModelRepositoryFake()
        let service = makeVoiceInputService(permission: permission, repository: repository, supported: false)

        do {
            try await prepareAdmittedVoiceInputService(service)
            XCTFail("Expected an unsupported-architecture error")
        } catch {
            XCTAssertEqual(error as? VoiceInputServiceError, .unsupportedArchitecture)
        }
        XCTAssertEqual(permission.requestCount, 0)
        let preparationModes = await repository.preparationModes
        XCTAssertEqual(preparationModes, [])
    }

    func testLateAudioFromCancelledGenerationIsIgnored() async throws {
        let inference = VoiceInputInferenceFake()
        await inference.setProcessOutputs(["should not be used"])
        let firstCapture = VoiceInputAudioCaptureFake()
        let secondCapture = VoiceInputAudioCaptureFake()
        let captures = VoiceInputCaptureFactoryFake(captures: [firstCapture, secondCapture])
        let service = DefaultVoiceInputService(
            permissionProvider: VoiceInputPermissionFake(status: .authorized),
            modelRepository: VoiceInputModelRepositoryFake(),
            inferenceEngine: inference,
            audioCaptureFactory: { captures.makeCapture() },
            suddenTerminationController: SuddenTerminationControllerFake(),
            memoryPressureMonitor: MemoryPressureMonitorFake(),
            architectureCheck: { true }
        )
        try await prepareAdmittedVoiceInputService(service)
        let firstSession = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
        await service.cancelRecognition(firstSession)
        let secondSession = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }

        await firstCapture.emit(.audio(makeVoiceInputPCMTransfer()))
        await service.cancelRecognition(secondSession)

        let operations = await inference.operations
        XCTAssertFalse(operations.contains("process"))
    }
}

extension VoiceInputInferenceFake {
    func setLoadErrors(_ errors: [VoiceInputServiceError]) {
        loadErrors = errors
    }

    func setProcessOutputs(_ outputs: [String]) {
        processOutputs = outputs
    }

    func setFinalOutput(_ output: String) {
        finalOutput = output
    }

    func setResetError(_ error: VoiceInputInferenceFakeError?) {
        resetError = error
    }

    func setFinalizationIsReusable(_ isReusable: Bool) {
        finalizationIsReusable = isReusable
    }

    func setFinalFailure(_ error: VoiceInputInferenceFakeError?, resetIsReusable: Bool = true) {
        finalError = error
        failureResetIsReusable = resetIsReusable
    }

    func setCancelAndResetIsReusable(_ isReusable: Bool) {
        cancelAndResetIsReusable = isReusable
    }
}
