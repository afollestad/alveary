import Dispatch
import XCTest

@testable import Alveary

@MainActor
extension DefaultVoiceInputServiceTests {
    func testSuddenTerminationLeaseSerializesControllerTransitions() async {
        let controller = BlockingSuddenTerminationController()
        let lease = VoiceInputSuddenTerminationLease(controller: controller)
        let acquireTask = Task.detached {
            lease.acquire()
        }
        XCTAssertTrue(controller.waitForFirstDisableToStart())

        let releaseTask = Task.detached {
            controller.noteReleaseAttemptStarted()
            lease.release()
        }
        XCTAssertTrue(controller.waitForReleaseAttemptToStart())
        XCTAssertFalse(controller.waitForEnableBeforeFirstDisableCompletes())

        controller.completeFirstDisable()
        await acquireTask.value
        await releaseTask.value

        XCTAssertEqual(controller.events, [.disableStarted, .disableCompleted, .enable])
        XCTAssertEqual(controller.disableCount, 1)
        XCTAssertEqual(controller.enableCount, 1)

        lease.acquire()
        lease.acquire()
        lease.release()
        lease.release()
        XCTAssertEqual(controller.disableCount, 2)
        XCTAssertEqual(controller.enableCount, 2)
    }

    func testFailedFinishAndResetCommitsPartialThenRequiresFreshPreparation() async throws {
        let inference = VoiceInputInferenceFake()
        await inference.setProcessOutputs(["latest partial"])
        await inference.setFinalFailure(
            VoiceInputInferenceFakeError(message: "finish failed"),
            resetIsReusable: false
        )
        let capture = VoiceInputAudioCaptureFake()
        let service = makeVoiceInputService(inference: inference, capture: capture)
        try await prepareAdmittedVoiceInputService(service)
        let firstSession = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
        await capture.emit(.audio(makeVoiceInputPCMTransfer()))

        let result = await service.stopRecognition(firstSession)

        XCTAssertEqual(result.transcript, "latest partial")
        XCTAssertEqual(result.error, .inference("finish failed"))
        do {
            _ = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
            XCTFail("Expected failed reset to require preparation")
        } catch {
            XCTAssertEqual(
                error as? VoiceInputServiceError,
                .modelLoad("The voice model has not been prepared.")
            )
        }

        await inference.setFinalFailure(nil)
        try await prepareAdmittedVoiceInputService(service)
        let secondSession = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
        await service.cancelRecognition(secondSession)

        let operations = await inference.operations
        XCTAssertEqual(
            operations,
            ["load", "reset", "process", "finish", "cleanup", "load", "reset", "cancel"]
        )
    }

    func testUnhealthyPostFinalResetPreservesTranscriptAndRequiresFreshPreparation() async throws {
        let inference = VoiceInputInferenceFake()
        await inference.setFinalOutput("newer final")
        await inference.setFinalizationIsReusable(false)
        let capture = VoiceInputAudioCaptureFake()
        let service = makeVoiceInputService(inference: inference, capture: capture)
        try await prepareAdmittedVoiceInputService(service)
        let firstSession = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }

        let result = await service.stopRecognition(firstSession)

        XCTAssertEqual(result.transcript, "newer final")
        do {
            _ = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
            XCTFail("Expected an unhealthy manager to require preparation")
        } catch {
            XCTAssertEqual(
                error as? VoiceInputServiceError,
                .modelLoad("The voice model has not been prepared.")
            )
        }

        await inference.setFinalizationIsReusable(true)
        try await prepareAdmittedVoiceInputService(service)
        let secondSession = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
        await service.cancelRecognition(secondSession)

        let operations = await inference.operations
        XCTAssertEqual(operations, ["load", "reset", "finish", "cleanup", "load", "reset", "cancel"])
    }

    func testTerminationRequestedDuringCaptureStartRejectsLateSession() async throws {
        let capture = VoiceInputAudioCaptureFake()
        let suddenTermination = SuddenTerminationControllerFake()
        capture.setSuspendsStart(true)
        let service = makeVoiceInputService(capture: capture, suddenTermination: suddenTermination)
        try await prepareAdmittedVoiceInputService(service)
        let beginTask = Task {
            try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
        }
        for _ in 0..<500 where !capture.hasPendingStart {
            await Task.yield()
        }
        XCTAssertTrue(capture.hasPendingStart)
        XCTAssertEqual(suddenTermination.disableCount, 1)

        let terminationCompleted = VoiceInputAtomicFlag()
        let terminationTask = Task.detached {
            service.prepareForTerminationSynchronously()
            terminationCompleted.set()
        }
        for _ in 0..<500 where !terminationCompleted.value {
            await Task.yield()
        }
        XCTAssertTrue(terminationCompleted.value)
        XCTAssertTrue(service.terminationWasRequestedForTesting)
        XCTAssertTrue(capture.hasPendingStart)
        capture.resumePendingStart()
        await terminationTask.value

        do {
            _ = try await beginTask.value
            XCTFail("Expected termination to reject the starting session")
        } catch {
            XCTAssertEqual(error as? VoiceInputServiceError, .recognitionSessionExpired)
        }
        XCTAssertEqual(capture.startCount, 1)
        XCTAssertEqual(capture.synchronousDiscardCount, 1)
        XCTAssertEqual(suddenTermination.disableCount, 1)
        XCTAssertEqual(suddenTermination.enableCount, 1)
    }

    func testCaptureStartFailureBalancesSuddenTerminationLease() async throws {
        let capture = VoiceInputAudioCaptureFake()
        capture.startError = .noInputDevice
        let suddenTermination = SuddenTerminationControllerFake()
        let service = makeVoiceInputService(capture: capture, suddenTermination: suddenTermination)
        try await prepareAdmittedVoiceInputService(service)

        do {
            _ = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
            XCTFail("Expected capture startup failure")
        } catch {
            XCTAssertEqual(error as? VoiceInputServiceError, .noInputDevice)
        }

        XCTAssertEqual(suddenTermination.disableCount, 1)
        XCTAssertEqual(suddenTermination.enableCount, 1)
    }

    func testUnhealthyCancelResetRequiresFreshPreparation() async throws {
        let inference = VoiceInputInferenceFake()
        let service = makeVoiceInputService(inference: inference)
        try await prepareAdmittedVoiceInputService(service)
        let firstSession = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
        await inference.setCancelAndResetIsReusable(false)

        await service.cancelRecognition(firstSession)

        do {
            _ = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
            XCTFail("Expected an unhealthy cancellation reset to require preparation")
        } catch {
            XCTAssertEqual(
                error as? VoiceInputServiceError,
                .modelLoad("The voice model has not been prepared.")
            )
        }

        await inference.setCancelAndResetIsReusable(true)
        try await prepareAdmittedVoiceInputService(service)
        let secondSession = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }
        await service.cancelRecognition(secondSession)

        let operations = await inference.operations
        XCTAssertEqual(operations, ["load", "reset", "cancel", "cleanup", "load", "reset", "cancel"])
    }

    func testSynchronousShutdownClosesCaptureImmediately() async throws {
        let capture = VoiceInputAudioCaptureFake()
        let suddenTermination = SuddenTerminationControllerFake()
        let service = makeVoiceInputService(capture: capture, suddenTermination: suddenTermination)
        try await prepareAdmittedVoiceInputService(service)
        let session = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }

        service.shutdownCaptureSynchronously(for: VoiceInputRecognitionSession())
        XCTAssertEqual(capture.synchronousShutdownCount, 0)

        service.shutdownCaptureSynchronously(for: session)

        XCTAssertEqual(capture.synchronousShutdownCount, 1)
        XCTAssertEqual(suddenTermination.enableCount, 0)
        await service.shutdown()
        XCTAssertEqual(suddenTermination.enableCount, 1)
    }

    func testTerminationPreparationStopsCaptureAndReleasesSuddenTerminationSynchronously() async throws {
        let capture = VoiceInputAudioCaptureFake()
        let suddenTermination = SuddenTerminationControllerFake()
        let service = makeVoiceInputService(capture: capture, suddenTermination: suddenTermination)
        try await prepareAdmittedVoiceInputService(service)
        _ = try await service.beginRecognition(attempt: VoiceInputRecognitionAttempt()) { _ in }

        service.prepareForTerminationSynchronously()

        XCTAssertEqual(capture.synchronousDiscardCount, 1)
        XCTAssertEqual(suddenTermination.enableCount, 1)
        service.prepareForTerminationSynchronously()
        XCTAssertEqual(suddenTermination.enableCount, 1)
        await service.shutdown()
    }

    func testTerminationRejectsLateCallbacksAndSkipsFinishDuringSuspendedDiscard() async throws {
        let inference = VoiceInputInferenceFake()
        await inference.setProcessOutputs(["late partial"])
        let capture = VoiceInputAudioCaptureFake()
        capture.setSuspendsDiscard(true)
        let updates = VoiceInputUpdateRecorder()
        let suddenTermination = SuddenTerminationControllerFake()
        let service = makeVoiceInputService(
            inference: inference,
            capture: capture,
            suddenTermination: suddenTermination
        )
        try await prepareAdmittedVoiceInputService(service)
        _ = try await service.beginRecognition(
            attempt: VoiceInputRecognitionAttempt(),
            onUpdate: updates.append
        )

        service.prepareForTerminationSynchronously()
        let shutdownTask = Task { await service.shutdown() }
        for _ in 0..<500 {
            if capture.hasPendingDiscard { break }
            await Task.yield()
        }
        XCTAssertTrue(capture.hasPendingDiscard)

        await capture.emit(.failed(.deviceConfigurationChanged))
        await capture.emit(.audio(makeVoiceInputPCMTransfer()))
        capture.resumePendingDiscard()
        await shutdownTask.value

        let inferenceOperations = await inference.operations
        XCTAssertFalse(inferenceOperations.contains("finish"))
        XCTAssertFalse(inferenceOperations.contains("process"))
        XCTAssertEqual(inferenceOperations.filter { $0 == "cancel" }.count, 1)
        XCTAssertEqual(updates.updates, [])
        XCTAssertEqual(capture.discardCount, 1)
        XCTAssertEqual(suddenTermination.disableCount, 1)
        XCTAssertEqual(suddenTermination.enableCount, 1)
    }

    func testSynchronousShutdownRejectsCaptureAfterSuspendedResetReturns() async throws {
        let inference = SuspendingResetVoiceInputInferenceFake()
        let capture = VoiceInputAudioCaptureFake()
        let service = makeVoiceInputService(inference: inference, capture: capture)
        try await prepareAdmittedVoiceInputService(service)
        let attempt = VoiceInputRecognitionAttempt()
        let beginTask = Task {
            try await service.beginRecognition(attempt: attempt) { _ in }
        }
        for _ in 0..<500 {
            if await inference.hasPendingReset {
                break
            }
            await Task.yield()
        }
        let resetIsPending = await inference.hasPendingReset
        XCTAssertTrue(resetIsPending)

        attempt.cancelSynchronously()
        await inference.resumeReset()

        do {
            _ = try await beginTask.value
            XCTFail("Expected the cancelled startup to be rejected")
        } catch {
            XCTAssertEqual(error as? VoiceInputServiceError, .recognitionSessionExpired)
        }
        XCTAssertEqual(capture.startCount, 0)
    }

    func testStartupCancellationAfterBeginReturnsRejectsFailureFinalization() async throws {
        let inference = VoiceInputInferenceFake()
        let capture = VoiceInputAudioCaptureFake()
        let suddenTermination = SuddenTerminationControllerFake()
        let service = makeVoiceInputService(
            inference: inference,
            capture: capture,
            suddenTermination: suddenTermination
        )
        try await prepareAdmittedVoiceInputService(service)
        let attempt = VoiceInputRecognitionAttempt()
        let session = try await service.beginRecognition(attempt: attempt) { _ in }

        attempt.cancelSynchronously()
        await capture.emit(.failed(.deviceConfigurationChanged))
        await service.cancelRecognition(session)

        let inferenceOperations = await inference.operations
        XCTAssertFalse(inferenceOperations.contains("finish"))
        XCTAssertEqual(inferenceOperations.filter { $0 == "cancel" }.count, 1)
        XCTAssertEqual(capture.synchronousDiscardCount, 1)
        XCTAssertEqual(suddenTermination.disableCount, 1)
        XCTAssertEqual(suddenTermination.enableCount, 1)
    }
}

private final class VoiceInputAtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool {
        lock.withLock { storage }
    }

    func set() {
        lock.withLock { storage = true }
    }
}

private final class BlockingSuddenTerminationController: VoiceInputSuddenTerminationControlling, @unchecked Sendable {
    enum Event: Equatable {
        case disableStarted
        case disableCompleted
        case enable
    }

    private let lock = NSLock()
    private let firstDisableStarted = DispatchSemaphore(value: 0)
    private let firstDisableCompletion = DispatchSemaphore(value: 0)
    private let releaseAttemptStarted = DispatchSemaphore(value: 0)
    private let enableStarted = DispatchSemaphore(value: 0)
    private var eventStorage: [Event] = []
    private var disableCountStorage = 0
    private var enableCountStorage = 0

    var events: [Event] {
        lock.withLock { eventStorage }
    }

    var disableCount: Int {
        lock.withLock { disableCountStorage }
    }

    var enableCount: Int {
        lock.withLock { enableCountStorage }
    }

    func disable() {
        let isFirstDisable = lock.withLock {
            disableCountStorage += 1
            eventStorage.append(.disableStarted)
            return disableCountStorage == 1
        }
        if isFirstDisable {
            firstDisableStarted.signal()
            firstDisableCompletion.wait()
        }
        lock.withLock {
            eventStorage.append(.disableCompleted)
        }
    }

    func enable() {
        lock.withLock {
            enableCountStorage += 1
            eventStorage.append(.enable)
        }
        enableStarted.signal()
    }

    func noteReleaseAttemptStarted() {
        releaseAttemptStarted.signal()
    }

    func waitForFirstDisableToStart() -> Bool {
        firstDisableStarted.wait(timeout: .now() + 1) == .success
    }

    func waitForReleaseAttemptToStart() -> Bool {
        releaseAttemptStarted.wait(timeout: .now() + 1) == .success
    }

    func waitForEnableBeforeFirstDisableCompletes() -> Bool {
        enableStarted.wait(timeout: .now() + 0.25) == .success
    }

    func completeFirstDisable() {
        firstDisableCompletion.signal()
    }
}
