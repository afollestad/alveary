import Darwin
import Foundation

enum TerminalProcessWaitStatus: Equatable, Sendable {
    case exited
    case stillRunning
    case unavailable
}

struct TerminalProcessTerminationFallback: Sendable {
    var graceDelay: Duration = .milliseconds(600)
    var pollDelay: Duration = .milliseconds(80)
    var maxReapAttempts = 6
    var waitStatus: @Sendable (pid_t) -> TerminalProcessWaitStatus = Self.liveWaitStatus
    var signal: @Sendable (pid_t, Int32) -> Void = { pid, signal in
        _ = Darwin.kill(pid, signal)
    }
    var sleep: @Sendable (Duration) async -> Void = { duration in
        try? await Task.sleep(for: duration)
    }

    func schedule(pid: pid_t) {
        guard pid > 0 else {
            return
        }

        Task.detached {
            await run(pid: pid)
        }
    }

    func run(pid: pid_t) async {
        guard pid > 0 else {
            return
        }

        await sleep(graceDelay)

        switch waitStatus(pid) {
        case .exited, .unavailable:
            return
        case .stillRunning:
            signal(pid, SIGKILL)
        }

        for _ in 0..<maxReapAttempts {
            await sleep(pollDelay)

            switch waitStatus(pid) {
            case .exited, .unavailable:
                return
            case .stillRunning:
                continue
            }
        }
    }

    private static func liveWaitStatus(pid: pid_t) -> TerminalProcessWaitStatus {
        var status: Int32 = 0
        errno = 0
        let result = waitpid(pid, &status, WNOHANG)

        if result == pid {
            return .exited
        }
        if result == 0 {
            return .stillRunning
        }

        return .unavailable
    }
}
