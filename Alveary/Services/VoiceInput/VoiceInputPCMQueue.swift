import Foundation

final class VoiceInputPCMQueue: @unchecked Sendable {
    enum Next {
        case audio(VoiceInputCopiedPCM)
        case failure(VoiceInputServiceError)
        case finished
    }

    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
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
            semaphore.signal()
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
            semaphore.signal()
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
            semaphore.signal()
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
            semaphore.signal()
        }
    }

    func close() {
        let shouldSignal = lock.withLock { () -> Bool in
            guard !admissionClosed else { return false }
            admissionClosed = true
            return true
        }
        if shouldSignal {
            semaphore.signal()
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
            semaphore.signal()
        }
    }

    func waitForWork() {
        semaphore.wait()
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

    func complete(duration: TimeInterval) {
        lock.withLock {
            bufferedDuration = max(0, bufferedDuration - duration)
        }
    }
}
