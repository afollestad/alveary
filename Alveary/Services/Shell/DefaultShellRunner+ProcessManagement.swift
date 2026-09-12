import Darwin
import Foundation

struct ShellOutputCapture: Sendable {
    let data: Data
    let wasTruncated: Bool
    let incomplete: Bool
}

struct ShellExecutionCapture: Sendable {
    let didFinish: Bool
    let inputCompleted: Bool
    let standardOutput: ShellOutputCapture
    let standardError: ShellOutputCapture
}

struct ShellProcessPipes: @unchecked Sendable {
    let standardInput: Pipe?
    let standardOutput: Pipe
    let standardError: Pipe
    let stopController: ShellIOStopController?

    init(process: Process, options: ShellRunOptions) {
        switch options.standardInput {
        case .inherit:
            standardInput = nil
        case .nullDevice:
            standardInput = nil
            process.standardInput = FileHandle.nullDevice
        case .text:
            let pipe = Pipe()
            standardInput = pipe
            process.standardInput = pipe
        }
        standardOutput = Pipe()
        standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        stopController = options.processGroupPolicy == .create ? ShellIOStopController() : nil
    }

    func closeParentEnds() {
        try? standardInput?.fileHandleForReading.close()
        try? standardOutput.fileHandleForWriting.close()
        try? standardError.fileHandleForWriting.close()
    }
}

final class ProcessExitResumption: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    func resume(continuation: CheckedContinuation<Bool, Never>, returning value: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else {
            return false
        }
        hasResumed = true
        continuation.resume(returning: value)
        return true
    }
}

/// Holds worker registration through bounded TERM/KILL teardown of its whole process group.
final class ProcessTerminationController: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private let processGroupPolicy: ShellProcessGroupPolicy
    private let ioStopController: ShellIOStopController?
    private var processIdentifier: pid_t?
    private var hasRequestedTermination = false
    private var terminationTask: Task<Void, Never>?

    init(
        process: Process,
        processGroupPolicy: ShellProcessGroupPolicy,
        ioStopController: ShellIOStopController?
    ) {
        self.process = process
        self.processGroupPolicy = processGroupPolicy
        self.ioStopController = ioStopController
    }

    func didLaunch() {
        lock.withLock {
            processIdentifier = process.processIdentifier
        }
    }

    func requestTermination() {
        let identifier: pid_t?
        let shouldScheduleForceKill: Bool

        lock.lock()
        guard !hasRequestedTermination else {
            lock.unlock()
            return
        }
        if processIdentifier == nil {
            guard process.isRunning else {
                lock.unlock()
                return
            }
            processIdentifier = process.processIdentifier
        }
        hasRequestedTermination = true
        identifier = processIdentifier
        if processGroupPolicy == .create, let identifier {
            shouldScheduleForceKill = Darwin.kill(-identifier, SIGTERM) == 0 || process.isRunning
            if process.isRunning, !Self.processGroupExists(identifier) {
                process.terminate()
            }
        } else if process.isRunning {
            shouldScheduleForceKill = true
            process.terminate()
        } else {
            shouldScheduleForceKill = false
        }
        if shouldScheduleForceKill, let identifier {
            terminationTask = Self.makeTerminationTask(
                process: process,
                processGroupPolicy: processGroupPolicy,
                identifier: identifier
            )
        }
        lock.unlock()
        ioStopController?.beginDeadline()
    }

    func awaitTermination() async {
        let task = lock.withLock { terminationTask }
        await task?.value
    }

    private static func makeTerminationTask(
        process: Process,
        processGroupPolicy: ShellProcessGroupPolicy,
        identifier: pid_t
    ) -> Task<Void, Never> {
        Task {
            let clock = ContinuousClock()
            let graceDeadline = clock.now.advanced(by: .seconds(2))
            while isActive(process: process, processGroupPolicy: processGroupPolicy, identifier: identifier),
                  clock.now < graceDeadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
            guard isActive(process: process, processGroupPolicy: processGroupPolicy, identifier: identifier) else {
                return
            }
            if processGroupPolicy == .create {
                if Darwin.kill(-identifier, SIGKILL) != 0, process.isRunning {
                    _ = Darwin.kill(identifier, SIGKILL)
                }
            } else if process.isRunning {
                _ = Darwin.kill(identifier, SIGKILL)
            }

            let deadline = clock.now.advanced(by: .seconds(1))
            while isActive(process: process, processGroupPolicy: processGroupPolicy, identifier: identifier),
                  clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    private static func processGroupExists(_ identifier: pid_t) -> Bool {
        Darwin.kill(-identifier, 0) == 0 || errno == EPERM
    }

    private static func isActive(
        process: Process,
        processGroupPolicy: ShellProcessGroupPolicy,
        identifier: pid_t
    ) -> Bool {
        process.isRunning || processGroupPolicy == .create && processGroupExists(identifier)
    }
}

final class ShellIOStopController: @unchecked Sendable {
    private let state = LockedState<Double?>(nil)

    var shouldStop: Bool {
        state.withLock { deadline in
            deadline.map { ProcessInfo.processInfo.systemUptime >= $0 } ?? false
        }
    }

    func beginDeadline() {
        state.withLock { deadline in
            if deadline == nil {
                deadline = ProcessInfo.processInfo.systemUptime + 3
            }
        }
    }
}
