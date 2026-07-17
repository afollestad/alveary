@testable import Alveary
@preconcurrency import AVFoundation
import Dispatch
import Foundation
import XCTest

@MainActor
final class DefaultVoiceInputAudioCaptureTests: XCTestCase {
    func testSynchronousShutdownWaitsForBackendFactoryRegistration() async {
        let backend = VoiceInputAudioCaptureBackendFake()
        let factoryBegan = DispatchSemaphore(value: 0)
        let factoryCanReturn = DispatchSemaphore(value: 0)
        let capture = DefaultVoiceInputAudioCapture(backendFactory: {
            factoryBegan.signal()
            factoryCanReturn.wait()
            return backend
        })
        let startTask = Task.detached { () -> VoiceInputServiceError? in
            do {
                try capture.start(generation: 10) { _ in }
                return nil
            } catch {
                return error as? VoiceInputServiceError
            }
        }

        XCTAssertEqual(factoryBegan.wait(timeout: .now() + 2), .success)
        let shutdownBegan = DispatchSemaphore(value: 0)
        let shutdownCompleted = DispatchSemaphore(value: 0)
        let shutdownTask = Task.detached {
            shutdownBegan.signal()
            capture.shutdownSynchronously()
            shutdownCompleted.signal()
        }

        XCTAssertEqual(shutdownBegan.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(shutdownCompleted.wait(timeout: .now() + 0.25), .timedOut)
        factoryCanReturn.signal()
        XCTAssertEqual(shutdownCompleted.wait(timeout: .now() + 1), .success)
        await shutdownTask.value
        XCTAssertEqual(backend.calls.stop, 1)
        XCTAssertEqual(backend.calls.reset, 1)

        let error = await startTask.value
        // Startup may win the post-factory lock race, but teardown must still finish before shutdown returns.
        XCTAssertTrue(error == nil || error == .recognitionSessionExpired)
        await capture.stopAndDrain()
        XCTAssertEqual(backend.calls.stop, 1)
        XCTAssertEqual(backend.calls.reset, 1)
    }

    func testSynchronousShutdownCancelsStartupWhileEngineIsPreparing() async {
        let backend = VoiceInputAudioCaptureBackendFake(blocksPrepare: true)
        let capture = DefaultVoiceInputAudioCapture(backendFactory: { backend })
        let startTask = Task.detached { () -> VoiceInputServiceError? in
            do {
                try capture.start(generation: 11) { _ in }
                return nil
            } catch {
                return error as? VoiceInputServiceError
            }
        }

        XCTAssertEqual(backend.waitUntilPrepareBegins(), .success)
        let shutdownCompleted = DispatchSemaphore(value: 0)
        let shutdownTask = Task.detached {
            capture.shutdownSynchronously()
            shutdownCompleted.signal()
        }

        let immediateCalls = backend.calls
        XCTAssertEqual(immediateCalls.start, 0)
        XCTAssertEqual(immediateCalls.removeTap, 0)
        XCTAssertEqual(immediateCalls.stop, 0)
        XCTAssertEqual(immediateCalls.reset, 0)
        XCTAssertEqual(shutdownCompleted.wait(timeout: .now() + 0.25), .timedOut)

        backend.finishPrepare()
        XCTAssertEqual(shutdownCompleted.wait(timeout: .now() + 1), .success)
        await shutdownTask.value

        let error = await startTask.value
        XCTAssertEqual(error, .recognitionSessionExpired)
        await capture.stopAndDrain()

        let calls = backend.calls
        XCTAssertEqual(calls.installTap, 1)
        XCTAssertEqual(calls.prepare, 1)
        XCTAssertEqual(calls.start, 0)
        XCTAssertEqual(calls.installObservers, 1)
        XCTAssertEqual(calls.removeTap, 1)
        XCTAssertEqual(calls.removeObservers, 1)
        XCTAssertEqual(calls.stop, 1)
        XCTAssertEqual(calls.reset, 1)
    }

    func testRepeatedSynchronousTeardownRemovesTapAndObserversOnlyOnce() async throws {
        let backend = VoiceInputAudioCaptureBackendFake()
        let capture = DefaultVoiceInputAudioCapture(backendFactory: { backend })
        try capture.start(generation: 12) { _ in }

        capture.shutdownSynchronously()
        capture.shutdownAndDiscardSynchronously()
        capture.shutdownSynchronously()
        await capture.stopAndDrain()

        let calls = backend.calls
        XCTAssertEqual(calls.installTap, 1)
        XCTAssertEqual(calls.installObservers, 1)
        XCTAssertEqual(calls.removeTap, 1)
        XCTAssertEqual(calls.removeObservers, 1)
        XCTAssertEqual(calls.stop, 1)
        XCTAssertEqual(calls.reset, 1)
        XCTAssertFalse(backend.emit(makeBuffer(frameCount: 1_600)))
        XCTAssertFalse(backend.emitObserverFailure(.systemSleep))
    }

    func testSynchronousShutdownClosesQueueBeforeBackendTeardown() async throws {
        let backend = VoiceInputAudioCaptureBackendFake(blocksStop: true)
        let capture = DefaultVoiceInputAudioCapture(backendFactory: { backend })
        try capture.start(generation: 15) { _ in }

        let shutdownTask = Task.detached {
            capture.shutdownSynchronously()
        }
        XCTAssertEqual(backend.waitUntilStopBegins(), .success)
        XCTAssertFalse(backend.canReserveTestAudio(duration: 0.1))

        backend.finishStop()
        await shutdownTask.value
    }

    func testObserverFailureTerminatesWorkerAndObserversAreRemoved() async throws {
        let backend = VoiceInputAudioCaptureBackendFake()
        let events = AsyncStream.makeStream(of: VoiceInputCaptureEvent.self)
        let capture = DefaultVoiceInputAudioCapture(backendFactory: { backend })
        try capture.start(generation: 13) { event in
            events.continuation.yield(event)
        }
        var iterator = events.stream.makeAsyncIterator()

        XCTAssertTrue(backend.emitObserverFailure(.systemSleep))
        guard let event = await iterator.next() else {
            return XCTFail("Expected the worker to publish the observer failure")
        }
        guard case .failed(let error) = event else {
            return XCTFail("Expected a capture failure")
        }
        XCTAssertEqual(error, .systemSleep)

        await capture.stopAndDrain()
        events.continuation.finish()

        let calls = backend.calls
        XCTAssertEqual(calls.removeTap, 1)
        XCTAssertEqual(calls.removeObservers, 1)
        XCTAssertFalse(backend.emitObserverFailure(.deviceConfigurationChanged))
    }

    func testObserversAreInstalledBeforeTapAndBackendStartCanEmitFailure() async throws {
        let backend = VoiceInputAudioCaptureBackendFake(failureDuringStart: .deviceConfigurationChanged)
        let capture = DefaultVoiceInputAudioCapture(backendFactory: { backend })

        try capture.start(generation: 16) { _ in }

        XCTAssertTrue(backend.observersWereInstalledWhenTapCalled)
        XCTAssertTrue(backend.observersWereInstalledWhenStartCalled)
        XCTAssertTrue(backend.emittedFailureDuringStart)
        await capture.stopAndDrain()
        XCTAssertEqual(backend.calls.removeObservers, 1)
    }

    func testSustainedAudioBeyondQueueCapacityDrainsWithoutOverflow() async throws {
        let backend = VoiceInputAudioCaptureBackendFake()
        let events = AsyncStream.makeStream(of: VoiceInputCaptureEvent.self)
        let capture = DefaultVoiceInputAudioCapture(backendFactory: { backend })
        try capture.start(generation: 14) { event in
            events.continuation.yield(event)
        }
        var iterator = events.stream.makeAsyncIterator()
        let buffer = makeBuffer(frameCount: 1_600)

        for _ in 0..<30 {
            XCTAssertTrue(backend.emit(buffer))
            guard let event = await iterator.next() else {
                return XCTFail("Expected every admitted audio chunk to reach the worker")
            }
            guard case .audio(let transfer) = event else {
                return XCTFail("Expected audio without a queue overflow")
            }
            XCTAssertEqual(transfer.buffer.frameLength, 1_600)
        }

        await capture.stopAndDrain()
        events.continuation.finish()

        let calls = backend.calls
        XCTAssertEqual(calls.removeTap, 1)
        XCTAssertEqual(calls.removeObservers, 1)
    }

    private func makeBuffer(frameCount: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        return buffer
    }
}

private final class VoiceInputAudioCaptureBackendFake: VoiceInputAudioCaptureBackend, @unchecked Sendable {
    struct Calls: Equatable {
        var installTap = 0
        var prepare = 0
        var start = 0
        var installObservers = 0
        var stop = 0
        var removeTap = 0
        var removeObservers = 0
        var reset = 0
    }

    let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!

    private let lock = NSLock()
    private let prepareBegan = DispatchSemaphore(value: 0)
    private let prepareFinished = DispatchSemaphore(value: 0)
    private let stopBegan = DispatchSemaphore(value: 0)
    private let stopFinished = DispatchSemaphore(value: 0)
    private let blocksPrepare: Bool
    private let blocksStop: Bool
    private let failureDuringStart: VoiceInputServiceError?
    private var recordedCalls = Calls()
    private var tapQueue: VoiceInputPCMQueue?
    private var tapGeneration: UInt64?
    private var observerQueue: VoiceInputPCMQueue?
    private var observersInstalledAtTap = false
    private var observersInstalledAtStart = false
    private var emittedStartFailure = false

    init(
        blocksPrepare: Bool = false,
        blocksStop: Bool = false,
        failureDuringStart: VoiceInputServiceError? = nil
    ) {
        self.blocksPrepare = blocksPrepare
        self.blocksStop = blocksStop
        self.failureDuringStart = failureDuringStart
    }

    var calls: Calls {
        lock.withLock { recordedCalls }
    }

    var observersWereInstalledWhenStartCalled: Bool {
        lock.withLock { observersInstalledAtStart }
    }

    var observersWereInstalledWhenTapCalled: Bool {
        lock.withLock { observersInstalledAtTap }
    }

    var emittedFailureDuringStart: Bool {
        lock.withLock { emittedStartFailure }
    }

    func installTap(
        frameCount: AVAudioFrameCount,
        format: AVAudioFormat,
        generation: UInt64,
        queue: VoiceInputPCMQueue
    ) throws {
        lock.withLock {
            recordedCalls.installTap += 1
            observersInstalledAtTap = observerQueue != nil
            tapQueue = queue
            tapGeneration = generation
        }
    }

    func prepare() {
        lock.withLock {
            recordedCalls.prepare += 1
        }
        guard blocksPrepare else { return }
        prepareBegan.signal()
        prepareFinished.wait()
    }

    func start() throws {
        let failureDestination = lock.withLock { () -> VoiceInputPCMQueue? in
            recordedCalls.start += 1
            observersInstalledAtStart = observerQueue != nil
            return observerQueue
        }
        if let failureDuringStart, let failureDestination {
            lock.withLock {
                emittedStartFailure = true
            }
            failureDestination.fail(failureDuringStart)
        }
    }

    func installObservers(queue: VoiceInputPCMQueue) {
        lock.withLock {
            recordedCalls.installObservers += 1
            observerQueue = queue
        }
    }

    func stop() {
        lock.withLock {
            recordedCalls.stop += 1
        }
        guard blocksStop else { return }
        stopBegan.signal()
        stopFinished.wait()
    }

    func removeTap() {
        lock.withLock {
            recordedCalls.removeTap += 1
            tapQueue = nil
            tapGeneration = nil
        }
    }

    func removeObservers() {
        lock.withLock {
            recordedCalls.removeObservers += 1
            observerQueue = nil
        }
    }

    func reset() {
        lock.withLock {
            recordedCalls.reset += 1
        }
    }

    func waitUntilPrepareBegins() -> DispatchTimeoutResult {
        prepareBegan.wait(timeout: .now() + 2)
    }

    func finishPrepare() {
        prepareFinished.signal()
    }

    func waitUntilStopBegins() -> DispatchTimeoutResult {
        stopBegan.wait(timeout: .now() + 2)
    }

    func finishStop() {
        stopFinished.signal()
    }

    func canReserveTestAudio(duration: TimeInterval) -> Bool {
        let destination = lock.withLock { () -> (VoiceInputPCMQueue, UInt64)? in
            guard let tapQueue, let tapGeneration else { return nil }
            return (tapQueue, tapGeneration)
        }
        guard let destination else { return false }
        let admitted = destination.0.reserve(duration: duration, generation: destination.1)
        if admitted {
            destination.0.cancelReservation(duration: duration)
        }
        return admitted
    }

    func emit(_ buffer: AVAudioPCMBuffer) -> Bool {
        let destination = lock.withLock { () -> (VoiceInputPCMQueue, UInt64)? in
            guard let tapQueue, let tapGeneration else { return nil }
            return (tapQueue, tapGeneration)
        }
        guard let destination else { return false }
        VoiceInputCopiedPCM.copyIfAdmitted(
            buffer,
            generation: destination.1,
            queue: destination.0
        )
        return true
    }

    func emitObserverFailure(_ error: VoiceInputServiceError) -> Bool {
        let queue = lock.withLock { observerQueue }
        guard let queue else { return false }
        queue.fail(error)
        return true
    }
}
