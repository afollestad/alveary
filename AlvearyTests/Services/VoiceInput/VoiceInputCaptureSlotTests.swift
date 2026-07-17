import Dispatch
import XCTest

@testable import Alveary

final class VoiceInputCaptureSlotTests: XCTestCase {
    func testTerminationWaitsForStartupCancellationTeardown() async throws {
        let slot = VoiceInputCaptureSlot()
        let capture = BlockingSynchronousCapture()
        let attemptID = UUID()
        let generation: UInt64 = 2
        let operationBegan = DispatchSemaphore(value: 0)
        let operationCanFinish = DispatchSemaphore(value: 0)
        XCTAssertTrue(slot.reserve(attemptID: attemptID, generation: generation))
        let context = VoiceInputCaptureSlot.StartContext(
            attemptID: attemptID,
            session: VoiceInputRecognitionSession(),
            generation: generation,
            finalizationGate: VoiceInputRecognitionFinalizationGate()
        )
        let startTask = Task.detached {
            try slot.start(capture, context: context) {
                operationBegan.signal()
                operationCanFinish.wait()
            }
        }
        XCTAssertEqual(operationBegan.wait(timeout: .now() + 1), .success)

        let cancellationCompleted = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            slot.cancelStartupSynchronously(attemptID: attemptID)
            cancellationCompleted.signal()
        }
        XCTAssertTrue(capture.waitForDiscardToStart())
        let terminationBegan = DispatchSemaphore(value: 0)
        let terminationCompleted = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            terminationBegan.signal()
            slot.terminateSynchronously()
            terminationCompleted.signal()
        }
        XCTAssertEqual(terminationBegan.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(terminationCompleted.wait(timeout: .now() + 0.25), .timedOut)

        capture.completeDiscard()
        XCTAssertEqual(cancellationCompleted.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(terminationCompleted.wait(timeout: .now() + 1), .success)
        operationCanFinish.signal()
        let started = try await startTask.value
        XCTAssertFalse(started)
        XCTAssertEqual(capture.discardCount, 1)
    }

    func testConcurrentTerminationWaitsForClaimedTeardown() async throws {
        let slot = VoiceInputCaptureSlot()
        let capture = BlockingSynchronousCapture()
        let attemptID = UUID()
        let generation: UInt64 = 3
        XCTAssertTrue(slot.reserve(attemptID: attemptID, generation: generation))
        XCTAssertTrue(try slot.start(
            capture,
            context: VoiceInputCaptureSlot.StartContext(
                attemptID: attemptID,
                session: VoiceInputRecognitionSession(),
                generation: generation,
                finalizationGate: VoiceInputRecognitionFinalizationGate()
            ),
            operation: {}
        ))

        let firstTermination = Task.detached {
            slot.terminateSynchronously()
        }
        XCTAssertTrue(capture.waitForDiscardToStart())
        let secondBegan = DispatchSemaphore(value: 0)
        let secondCompleted = DispatchSemaphore(value: 0)
        let secondTermination = Task.detached {
            secondBegan.signal()
            slot.terminateSynchronously()
            secondCompleted.signal()
        }
        XCTAssertEqual(secondBegan.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(secondCompleted.wait(timeout: .now() + 0.25), .timedOut)

        capture.completeDiscard()
        await firstTermination.value
        XCTAssertEqual(secondCompleted.wait(timeout: .now() + 1), .success)
        await secondTermination.value
        XCTAssertEqual(capture.discardCount, 1)
    }

    func testTerminationCannotReturnBeforeAdmissionAcquiresSuddenTerminationLease() async throws {
        let slot = VoiceInputCaptureSlot()
        let capture = VoiceInputAudioCaptureFake()
        let controller = BlockingCaptureTerminationController()
        let lease = VoiceInputSuddenTerminationLease(controller: controller)
        let attemptID = UUID()
        let generation: UInt64 = 1
        XCTAssertTrue(slot.reserve(attemptID: attemptID, generation: generation))

        let context = VoiceInputCaptureSlot.StartContext(
            attemptID: attemptID,
            session: VoiceInputRecognitionSession(),
            generation: generation,
            finalizationGate: VoiceInputRecognitionFinalizationGate()
        )
        let startTask = Task.detached {
            try slot.start(
                capture,
                context: context,
                onAdmission: {
                    lease.acquire()
                },
                operation: {}
            )
        }
        XCTAssertTrue(controller.waitForDisableToStart())

        let terminationCompleted = DispatchSemaphore(value: 0)
        let terminationTask = Task.detached {
            slot.terminateSynchronously()
            lease.release()
            terminationCompleted.signal()
        }
        for _ in 0..<500 where !slot.terminationWasRequested {
            await Task.yield()
        }
        XCTAssertTrue(slot.terminationWasRequested)
        XCTAssertEqual(terminationCompleted.wait(timeout: .now() + 0.25), .timedOut)

        controller.completeDisable()
        XCTAssertEqual(terminationCompleted.wait(timeout: .now() + 1), .success)
        await terminationTask.value

        let started = try await startTask.value
        XCTAssertFalse(started)
        XCTAssertEqual(capture.synchronousDiscardCount, 1)
        XCTAssertEqual(controller.disableCount, 1)
        XCTAssertEqual(controller.enableCount, 1)
    }
}

private final class BlockingSynchronousCapture: VoiceInputAudioCapturing, @unchecked Sendable {
    private let lock = NSLock()
    private let discardStarted = DispatchSemaphore(value: 0)
    private let discardCanFinish = DispatchSemaphore(value: 0)
    private var discardCountStorage = 0

    var discardCount: Int {
        lock.withLock { discardCountStorage }
    }

    func start(
        generation: UInt64,
        consumer: @escaping @Sendable (VoiceInputCaptureEvent) async -> Void
    ) throws {}

    func stopAndDrain() async {}
    func stopAndDiscard() async {}
    func shutdownSynchronously() {}

    func shutdownAndDiscardSynchronously() {
        lock.withLock {
            discardCountStorage += 1
        }
        discardStarted.signal()
        discardCanFinish.wait()
    }

    func waitForDiscardToStart() -> Bool {
        discardStarted.wait(timeout: .now() + 1) == .success
    }

    func completeDiscard() {
        discardCanFinish.signal()
    }
}

private final class BlockingCaptureTerminationController:
    VoiceInputSuddenTerminationControlling,
    @unchecked Sendable {
    private let lock = NSLock()
    private let disableStarted = DispatchSemaphore(value: 0)
    private let disableCompletion = DispatchSemaphore(value: 0)
    private var disableCountStorage = 0
    private var enableCountStorage = 0

    var disableCount: Int {
        lock.withLock { disableCountStorage }
    }

    var enableCount: Int {
        lock.withLock { enableCountStorage }
    }

    func disable() {
        lock.withLock {
            disableCountStorage += 1
        }
        disableStarted.signal()
        disableCompletion.wait()
    }

    func enable() {
        lock.withLock {
            enableCountStorage += 1
        }
    }

    func waitForDisableToStart() -> Bool {
        disableStarted.wait(timeout: .now() + 1) == .success
    }

    func completeDisable() {
        disableCompletion.signal()
    }
}
