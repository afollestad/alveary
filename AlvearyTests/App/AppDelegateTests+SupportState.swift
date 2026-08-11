import Foundation

@testable import Alveary

final class AppDelegateSharedState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedProcesses: [Process] = []
    private var shutdownCalls = 0
    private var storedShutdownOrderRecorder: AppDelegateShutdownOrderRecorder?

    var allProcessesSnapshot: [Process] {
        get {
            lock.withLock { storedProcesses }
        }
        set {
            lock.withLock { storedProcesses = newValue }
        }
    }

    var beginShutdownCalls: Int {
        get {
            lock.withLock { shutdownCalls }
        }
        set {
            lock.withLock { shutdownCalls = newValue }
        }
    }

    var shutdownOrderRecorder: AppDelegateShutdownOrderRecorder? {
        get {
            lock.withLock { storedShutdownOrderRecorder }
        }
        set {
            lock.withLock { storedShutdownOrderRecorder = newValue }
        }
    }
}

final class AppDelegateShutdownOrderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String] = []

    var values: [String] {
        lock.withLock { storedValues }
    }

    func record(_ value: String) {
        lock.withLock { storedValues.append(value) }
    }
}

final class AppDelegateProcessSignalState: @unchecked Sendable {
    struct SignalCall: Equatable {
        let pid: Int32
        let signal: Int32
    }

    private let lock = NSLock()
    private var activePIDs: Set<Int32>
    private var signals: [SignalCall] = []

    init(activePIDs: Set<Int32>) {
        self.activePIDs = activePIDs
    }

    func signal(pid: Int32, signal: Int32) {
        lock.withLock {
            signals.append(SignalCall(pid: pid, signal: signal))
            if signal == SIGTERM || signal == SIGKILL {
                activePIDs.remove(pid)
            }
        }
    }

    func contains(_ pid: Int32) -> Bool {
        lock.withLock { activePIDs.contains(pid) }
    }

    func recordedSignals() -> [SignalCall] {
        lock.withLock { signals }
    }
}

final class AppDelegateSuddenTerminationState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedDisableCalls = 0
    private var storedEnableCalls = 0

    var disableCalls: Int {
        lock.withLock { storedDisableCalls }
    }

    var enableCalls: Int {
        lock.withLock { storedEnableCalls }
    }

    func recordDisable() {
        lock.withLock { storedDisableCalls += 1 }
    }

    func recordEnable() {
        lock.withLock { storedEnableCalls += 1 }
    }
}

final class AppDelegateNotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

struct AppDelegateClaudeProcessListBuilder {
    private var lines: [String] = []

    func claude(pid: Int32, sessionId: String) -> AppDelegateClaudeProcessListBuilder {
        var copy = self
        copy.lines.append(" \(pid) /opt/homebrew/bin/claude --resume \(sessionId) --verbose")
        return copy
    }

    func other(pid: Int32, command: String) -> AppDelegateClaudeProcessListBuilder {
        var copy = self
        copy.lines.append(" \(pid) \(command)")
        return copy
    }

    func build() -> String {
        lines.joined(separator: "\n") + "\n"
    }
}

struct AppDelegateWaitTimeoutError: LocalizedError {
    let description: String

    var errorDescription: String? {
        description
    }
}
