import Foundation

/// Hands copied tap audio to the capture worker. Producers (the real-time tap, the main thread,
/// backend observers) never block; the worker suspends in `waitForWork()` between drains.
///
/// Producers wake the worker through `wakeSource`, never by resuming its continuation directly:
/// the real-time tap must not schedule Swift task work, so it only merges data into the source,
/// which also coalesces a burst of wakes into one handler call. The handler does the resume on
/// its own queue.
final class VoiceInputPCMQueue: @unchecked Sendable {
    enum Next {
        case audio(VoiceInputCopiedPCM)
        case failure(VoiceInputServiceError)
        case finished
    }

    private let lock = NSLock()
    /// Set when a wake arrives with no worker suspended; the next `waitForWork()` returns at once.
    /// A flag rather than a count, because the worker drains everything `next()` offers after every
    /// wake, so coalesced wakes lose nothing.
    private var pendingWake = false
    private var suspendedWorker: CheckedContinuation<Void, Never>?
    private let wakeSource = DispatchSource.makeUserDataAddSource(
        queue: DispatchQueue(label: "com.afollestad.alveary.voice-input.pcm-wake", qos: .userInitiated)
    )
    private let generation: UInt64
    private let maximumDuration: TimeInterval
    private var entries: [VoiceInputCopiedPCM] = []
    private var bufferedDuration = 0.0
    private var pendingReservations = 0
    private var admissionClosed = false
    private var discarding = false
    private var terminalFailure: VoiceInputServiceError?
    private var terminalDelivered = false

    init(generation: UInt64, maximumDuration: TimeInterval) {
        self.generation = generation
        self.maximumDuration = maximumDuration
        wakeSource.setEventHandler { [weak self] in
            self?.resumeSuspendedWorker()
        }
        wakeSource.activate()
    }

    deinit {
        wakeSource.cancel()
    }

    func enqueue(_ buffer: VoiceInputCopiedPCM, generation: UInt64) {
        guard reserve(duration: buffer.duration, generation: generation) else {
            return
        }
        commitReserved(buffer)
    }

    func reserve(duration: TimeInterval, generation: UInt64) -> Bool {
        guard duration > 0, duration.isFinite else {
            return false
        }
        let result = lock.withLock { () -> (admitted: Bool, signal: Bool) in
            guard !admissionClosed, self.generation == generation else {
                return (false, false)
            }
            guard bufferedDuration + duration <= maximumDuration else {
                admissionClosed = true
                terminalFailure = .captureQueueOverflow
                return (false, true)
            }
            bufferedDuration += duration
            pendingReservations += 1
            return (true, false)
        }
        if result.signal {
            wakeWorker()
        }
        return result.admitted
    }

    func commitReserved(_ buffer: VoiceInputCopiedPCM) {
        let shouldSignal = lock.withLock { () -> Bool in
            guard pendingReservations > 0 else { return false }
            pendingReservations -= 1
            guard !discarding else {
                return pendingReservations == 0
            }
            entries.append(buffer)
            return true
        }
        if shouldSignal {
            wakeWorker()
        }
    }

    func cancelReservation(duration: TimeInterval) {
        let shouldSignal = lock.withLock { () -> Bool in
            guard pendingReservations > 0 else { return false }
            pendingReservations -= 1
            bufferedDuration = max(0, bufferedDuration - duration)
            return admissionClosed && pendingReservations == 0
        }
        if shouldSignal {
            wakeWorker()
        }
    }

    func fail(_ error: VoiceInputServiceError) {
        let shouldSignal = lock.withLock { () -> Bool in
            guard !admissionClosed,
                  !discarding,
                  terminalFailure == nil,
                  !terminalDelivered else { return false }
            admissionClosed = true
            terminalFailure = error
            return true
        }
        if shouldSignal {
            wakeWorker()
        }
    }

    func close() {
        let shouldSignal = lock.withLock { () -> Bool in
            guard !admissionClosed else { return false }
            admissionClosed = true
            return true
        }
        if shouldSignal {
            wakeWorker()
        }
    }

    func discard() {
        let shouldSignal = lock.withLock { () -> Bool in
            guard !discarding, !terminalDelivered else { return false }
            discarding = true
            admissionClosed = true
            entries.removeAll()
            bufferedDuration = 0
            terminalFailure = nil
            return true
        }
        if shouldSignal {
            wakeWorker()
        }
    }

    /// Suspends rather than blocking a thread: the worker runs on the cooperative pool, which never
    /// replaces a blocked thread, so a blocking wait held one of its few threads for the whole
    /// capture — with the pool limited to one thread, every other async job stalled behind it.
    func waitForWork() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock { () -> Bool in
                if pendingWake {
                    pendingWake = false
                    return true
                }
                suspendedWorker = continuation
                return false
            }
            if resumeNow {
                continuation.resume()
            }
        }
    }

    func next() -> Next? {
        lock.withLock {
            if !entries.isEmpty {
                return .audio(entries.removeFirst())
            }
            if pendingReservations > 0 {
                return nil
            }
            if let terminalFailure, !terminalDelivered {
                terminalDelivered = true
                return .failure(terminalFailure)
            }
            if admissionClosed {
                return .finished
            }
            return nil
        }
    }

    #if DEBUG
    var hasSuspendedWorkerForTesting: Bool {
        lock.withLock { suspendedWorker != nil }
    }
    #endif

    func complete(duration: TimeInterval) {
        lock.withLock {
            bufferedDuration = max(0, bufferedDuration - duration)
        }
    }

    private func wakeWorker() {
        wakeSource.add(data: 1)
    }

    private func resumeSuspendedWorker() {
        let worker = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            guard let worker = suspendedWorker else {
                pendingWake = true
                return nil
            }
            suspendedWorker = nil
            return worker
        }
        worker?.resume()
    }
}
