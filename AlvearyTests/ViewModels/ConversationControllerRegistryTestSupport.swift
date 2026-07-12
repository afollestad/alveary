import Foundation

@testable import Alveary

@MainActor
final class ControllerMaintenanceRecorder {
    private(set) var values: [String] = []
    private var flushFailuresRemaining: Int

    init(flushFailuresRemaining: Int = 0) {
        self.flushFailuresRemaining = flushFailuresRemaining
    }

    func record(_ value: String) {
        values.append(value)
    }

    func flush() throws {
        record("flush")
        guard flushFailuresRemaining > 0 else {
            return
        }
        flushFailuresRemaining -= 1
        throw ControllerMaintenanceError.flushFailed
    }
}

@MainActor
final class ControllerFlushGate {
    private(set) var flushCallCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func flush() async {
        flushCallCount += 1
        guard flushCallCount == 1 else {
            return
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class ControllerFailingFlushGate {
    private(set) var flushCallCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func flush() async throws {
        flushCallCount += 1
        guard flushCallCount == 1 else {
            return
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        throw ControllerMaintenanceError.flushFailed
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class ControllerOutcomeCollector {
    private(set) var values: [ConversationControllerOutcome] = []
    private var task: Task<Void, Never>?

    init(stream: AsyncStream<ConversationControllerOutcome>) {
        task = Task { [weak self] in
            for await outcome in stream {
                self?.values.append(outcome)
            }
        }
    }

    deinit {
        task?.cancel()
    }
}

enum ControllerMaintenanceError: Error {
    case flushFailed
}
