import Darwin
import Foundation
import XCTest

@testable import Alveary

final class TerminalProcessTerminationFallbackTests: XCTestCase {
    func testRunDoesNothingWhenChildAlreadyExited() async {
        let recorder = FallbackRecorder(statuses: [.exited])
        let fallback = makeFallback(recorder: recorder)

        await fallback.run(pid: 123)

        XCTAssertTrue(recorder.signals.isEmpty)
        XCTAssertEqual(recorder.waitCallCount, 1)
    }

    func testRunDoesNotSignalWhenChildIsUnavailable() async {
        let recorder = FallbackRecorder(statuses: [.unavailable])
        let fallback = makeFallback(recorder: recorder)

        await fallback.run(pid: 123)

        XCTAssertTrue(recorder.signals.isEmpty)
        XCTAssertEqual(recorder.waitCallCount, 1)
    }

    func testRunKillsAndReapsStillRunningChild() async {
        let recorder = FallbackRecorder(statuses: [.stillRunning, .stillRunning, .exited])
        let fallback = makeFallback(recorder: recorder)

        await fallback.run(pid: 123)

        XCTAssertEqual(recorder.signals.count, 1)
        XCTAssertEqual(recorder.signals.first?.pid, 123)
        XCTAssertEqual(recorder.signals.first?.signal, SIGKILL)
        XCTAssertEqual(recorder.waitCallCount, 3)
    }

    func testRunIgnoresInvalidPID() async {
        let recorder = FallbackRecorder(statuses: [.stillRunning])
        let fallback = makeFallback(recorder: recorder)

        await fallback.run(pid: 0)

        XCTAssertTrue(recorder.signals.isEmpty)
        XCTAssertEqual(recorder.waitCallCount, 0)
    }

    private func makeFallback(recorder: FallbackRecorder) -> TerminalProcessTerminationFallback {
        var fallback = TerminalProcessTerminationFallback()
        fallback.graceDelay = .zero
        fallback.pollDelay = .zero
        fallback.sleep = { _ in }
        fallback.waitStatus = { pid in
            recorder.nextStatus(pid: pid)
        }
        fallback.signal = { pid, signal in
            recorder.recordSignal(pid: pid, signal: signal)
        }
        return fallback
    }
}

private final class FallbackRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [TerminalProcessWaitStatus]
    private(set) var signals: [(pid: pid_t, signal: Int32)] = []
    private(set) var waitCallCount = 0

    init(statuses: [TerminalProcessWaitStatus]) {
        self.statuses = statuses
    }

    func nextStatus(pid: pid_t) -> TerminalProcessWaitStatus {
        lock.withLock {
            waitCallCount += 1
            guard !statuses.isEmpty else {
                return .unavailable
            }

            return statuses.removeFirst()
        }
    }

    func recordSignal(pid: pid_t, signal: Int32) {
        lock.withLock {
            signals.append((pid: pid, signal: signal))
        }
    }
}
