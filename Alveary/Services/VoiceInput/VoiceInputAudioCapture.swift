@preconcurrency import AVFoundation
import Foundation

final class DefaultVoiceInputAudioCapture: VoiceInputAudioCapturing, @unchecked Sendable {
    private static let captureDuration = 0.160
    private static let maximumQueuedDuration = 2.0

    private let stateLock = NSLock()
    private let backendOperationLock = NSLock()
    private let backendFactory: @Sendable () -> any VoiceInputAudioCaptureBackend
    private var state: CaptureState?
    private var startingID: UUID?
    private var startingCapture: StartingCaptureState?
    private var startupCancellationRequested = false
    private var isClosed = false
    private var workerTask: Task<Void, Never>?
    private var workerQueue: VoiceInputPCMQueue?

    init(engineFactory: @escaping @Sendable () -> AVAudioEngine = { AVAudioEngine() }) {
        backendFactory = {
            AVAudioEngineVoiceInputCaptureBackend(engine: engineFactory())
        }
    }

    init(backendFactory: @escaping @Sendable () -> any VoiceInputAudioCaptureBackend) {
        self.backendFactory = backendFactory
    }

    func start(
        generation: UInt64,
        consumer: @escaping @Sendable (VoiceInputCaptureEvent) async -> Void
    ) throws {
        let startupID = UUID()
        let resources = try stateLock.withLock { () throws -> StartupResources in
            guard !isClosed else { throw VoiceInputServiceError.recognitionSessionExpired }
            guard state == nil, startingID == nil else {
                throw VoiceInputServiceError.audioCapture("The microphone capture owner is already running.")
            }
            let backend = backendFactory()
            let format = backend.format
            guard format.sampleRate > 0,
                  format.sampleRate.isFinite,
                  format.channelCount > 0 else {
                throw VoiceInputServiceError.noInputDevice
            }
            let queue = VoiceInputPCMQueue(generation: generation, maximumDuration: Self.maximumQueuedDuration)
            let task = Task.detached(priority: .userInitiated) {
                await Self.runWorker(queue: queue, consumer: consumer)
            }
            startingID = startupID
            startupCancellationRequested = false
            workerTask = task
            workerQueue = queue
            startingCapture = StartingCaptureState(
                id: startupID,
                backend: backend
            )
            return StartupResources(
                backend: backend,
                format: format,
                queue: queue,
                task: task
            )
        }

        let context = StartEngineContext(
            generation: generation,
            startupID: startupID,
            queue: resources.queue,
            task: resources.task
        )
        try startEngine(
            resources.backend,
            format: resources.format,
            context: context
        )
    }

    func stopAndDrain() async {
        shutdownSynchronously()
        await finishWorker()
    }

    func stopAndDiscard() async {
        shutdownAndDiscardSynchronously()
        await finishWorker()
    }

    func shutdownSynchronously() {
        shutdownSynchronously(discardQueuedAudio: false)
    }

    func shutdownAndDiscardSynchronously() {
        shutdownSynchronously(discardQueuedAudio: true)
    }

    private func shutdownSynchronously(discardQueuedAudio: Bool) {
        let captured = stateLock.withLock { () -> ShutdownState in
            isClosed = true
            if startingID != nil {
                startupCancellationRequested = true
            }
            let activeCapture = state
            state = nil
            var startupTeardown: BackendTeardown?
            if var startingCapture, !startingCapture.teardownClaimed {
                backendOperationLock.lock()
                startingCapture.teardownClaimed = true
                self.startingCapture = startingCapture
                startupTeardown = BackendTeardown(
                    backend: startingCapture.backend,
                    tapInstalled: startingCapture.tapInstalled,
                    observersInstalled: startingCapture.observersInstalled,
                    operationLockIsHeld: true
                )
            } else if activeCapture != nil {
                backendOperationLock.lock()
            }
            let queue = workerQueue ?? activeCapture?.queue
            if discardQueuedAudio {
                queue?.discard()
            } else {
                queue?.close()
            }
            return ShutdownState(
                activeCapture: activeCapture,
                startupTeardown: startupTeardown
            )
        }

        if let startupTeardown = captured.startupTeardown {
            teardownBackend(startupTeardown)
        }
        if let activeCapture = captured.activeCapture {
            teardownBackend(
                BackendTeardown(
                    backend: activeCapture.backend,
                    tapInstalled: true,
                    observersInstalled: true,
                    operationLockIsHeld: captured.startupTeardown == nil
                )
            )
        }
        waitForBackendOperations()
    }

    private func startEngine(
        _ backend: any VoiceInputAudioCaptureBackend,
        format: AVAudioFormat,
        context: StartEngineContext
    ) throws {
        do {
            let frameCount = AVAudioFrameCount(max(1, Int(format.sampleRate * Self.captureDuration)))
            guard installObservers(on: backend, context: context) else {
                throw VoiceInputServiceError.recognitionSessionExpired
            }
            guard try installTap(
                on: backend,
                frameCount: frameCount,
                format: format,
                context: context
            ) else {
                throw VoiceInputServiceError.recognitionSessionExpired
            }
            guard prepareBackend(backend, startupID: context.startupID) else {
                throw VoiceInputServiceError.recognitionSessionExpired
            }
            guard startupCanContinue(context.startupID) else {
                throw VoiceInputServiceError.recognitionSessionExpired
            }
            guard try startBackend(backend, startupID: context.startupID) else {
                throw VoiceInputServiceError.recognitionSessionExpired
            }
            guard publishCapture(backend: backend, context: context) else {
                throw VoiceInputServiceError.recognitionSessionExpired
            }
        } catch {
            abandonStartup(
                context.startupID,
                backend: backend,
                queue: context.queue,
                task: context.task
            )
            if let serviceError = error as? VoiceInputServiceError {
                throw serviceError
            }
            throw VoiceInputServiceError.audioCapture(error.localizedDescription)
        }
    }

    private func installTap(
        on backend: any VoiceInputAudioCaptureBackend,
        frameCount: AVAudioFrameCount,
        format: AVAudioFormat,
        context: StartEngineContext
    ) throws -> Bool {
        try stateLock.withLock {
            guard startingID == context.startupID,
                  startingCapture?.id == context.startupID,
                  startingCapture?.teardownClaimed == false,
                  !startupCancellationRequested,
                  !isClosed else {
                return false
            }
            try backend.installTap(
                frameCount: frameCount,
                format: format,
                generation: context.generation,
                queue: context.queue
            )
            startingCapture?.tapInstalled = true
            return true
        }
    }

    private func startBackend(
        _ backend: any VoiceInputAudioCaptureBackend,
        startupID: UUID
    ) throws -> Bool {
        try stateLock.withLock {
            guard self.startingID == startupID,
                  startingCapture?.id == startupID,
                  startingCapture?.teardownClaimed == false,
                  !startupCancellationRequested,
                  !isClosed else {
                return false
            }
            try backend.start()
            return true
        }
    }

    private func prepareBackend(
        _ backend: any VoiceInputAudioCaptureBackend,
        startupID: UUID
    ) -> Bool {
        stateLock.lock()
        guard self.startingID == startupID,
              startingCapture?.id == startupID,
              startingCapture?.teardownClaimed == false,
              !startupCancellationRequested,
              !isClosed else {
            stateLock.unlock()
            return false
        }
        backendOperationLock.lock()
        stateLock.unlock()
        defer { backendOperationLock.unlock() }
        backend.prepare()
        return true
    }

    private func installObservers(
        on backend: any VoiceInputAudioCaptureBackend,
        context: StartEngineContext
    ) -> Bool {
        stateLock.withLock {
            guard startingID == context.startupID,
                  startingCapture?.id == context.startupID,
                  startingCapture?.teardownClaimed == false,
                  !startupCancellationRequested,
                  !isClosed else {
                return false
            }
            backend.installObservers(queue: context.queue)
            startingCapture?.observersInstalled = true
            return true
        }
    }

    private func publishCapture(
        backend: any VoiceInputAudioCaptureBackend,
        context: StartEngineContext
    ) -> Bool {
        stateLock.withLock {
            guard startingID == context.startupID,
                  startingCapture?.id == context.startupID,
                  startingCapture?.teardownClaimed == false,
                  !startupCancellationRequested,
                  !isClosed else {
                return false
            }
            state = CaptureState(
                backend: backend,
                queue: context.queue
            )
            startingID = nil
            startingCapture = nil
            return true
        }
    }

    private func startupCanContinue(_ startupID: UUID) -> Bool {
        stateLock.withLock {
            startingID == startupID && !startupCancellationRequested
        }
    }

    private func abandonStartup(
        _ startupID: UUID,
        backend: any VoiceInputAudioCaptureBackend,
        queue: VoiceInputPCMQueue,
        task: Task<Void, Never>
    ) {
        let teardown = stateLock.withLock { () -> BackendTeardown? in
            var teardown: BackendTeardown?
            if var startingCapture, startingCapture.id == startupID {
                if !startingCapture.teardownClaimed {
                    backendOperationLock.lock()
                    startingCapture.teardownClaimed = true
                    teardown = BackendTeardown(
                        backend: startingCapture.backend,
                        tapInstalled: startingCapture.tapInstalled,
                        observersInstalled: startingCapture.observersInstalled,
                        operationLockIsHeld: true
                    )
                }
                self.startingCapture = nil
            } else {
                teardown = BackendTeardown(
                    backend: backend,
                    tapInstalled: false,
                    observersInstalled: false,
                    operationLockIsHeld: false
                )
            }
            if startingID == startupID {
                startingID = nil
                startupCancellationRequested = false
            }
            if workerQueue === queue {
                workerTask = nil
                workerQueue = nil
            }
            return teardown
        }
        queue.discard()
        task.cancel()
        if let teardown {
            teardownBackend(teardown)
        }
    }

    private func teardownBackend(_ teardown: BackendTeardown) {
        if teardown.operationLockIsHeld {
            defer { backendOperationLock.unlock() }
            performBackendTeardown(teardown)
        } else {
            backendOperationLock.withLock {
                performBackendTeardown(teardown)
            }
        }
    }

    private func performBackendTeardown(_ teardown: BackendTeardown) {
        teardown.backend.stop()
        if teardown.tapInstalled {
            teardown.backend.removeTap()
        }
        if teardown.observersInstalled {
            teardown.backend.removeObservers()
        }
        teardown.backend.reset()
    }

    private func waitForBackendOperations() {
        backendOperationLock.withLock {}
    }

    private func finishWorker() async {
        let pending = stateLock.withLock { (workerTask, workerQueue) }
        await pending.0?.value
        stateLock.withLock {
            guard let pendingQueue = pending.1,
                  workerQueue === pendingQueue else { return }
            workerTask = nil
            workerQueue = nil
        }
    }

    deinit {
        shutdownSynchronously()
        workerTask?.cancel()
    }

    private static func runWorker(
        queue: VoiceInputPCMQueue,
        consumer: @escaping @Sendable (VoiceInputCaptureEvent) async -> Void
    ) async {
        while !Task.isCancelled {
            queue.waitForWork()
            while let next = queue.next() {
                switch next {
                case .audio(let copied):
                    do {
                        let transfer = try copied.makeTransfer()
                        await consumer(.audio(transfer))
                    } catch {
                        queue.complete(duration: copied.duration)
                        await consumer(.failed(.audioCapture(error.localizedDescription)))
                        return
                    }
                    queue.complete(duration: copied.duration)
                case .failure(let error):
                    await consumer(.failed(error))
                    return
                case .finished:
                    return
                }
            }
        }
    }
}

private struct CaptureState {
    let backend: any VoiceInputAudioCaptureBackend
    let queue: VoiceInputPCMQueue
}

private struct StartingCaptureState {
    let id: UUID
    let backend: any VoiceInputAudioCaptureBackend
    var tapInstalled = false
    var observersInstalled = false
    var teardownClaimed = false
}

private struct BackendTeardown {
    let backend: any VoiceInputAudioCaptureBackend
    let tapInstalled: Bool
    let observersInstalled: Bool
    let operationLockIsHeld: Bool
}

private struct ShutdownState {
    let activeCapture: CaptureState?
    let startupTeardown: BackendTeardown?
}

private struct StartEngineContext {
    let generation: UInt64
    let startupID: UUID
    let queue: VoiceInputPCMQueue
    let task: Task<Void, Never>
}

private struct StartupResources {
    let backend: any VoiceInputAudioCaptureBackend
    let format: AVAudioFormat
    let queue: VoiceInputPCMQueue
    let task: Task<Void, Never>
}
