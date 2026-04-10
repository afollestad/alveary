import Darwin
import Foundation

final class DefaultShellRunner: ShellRunner, @unchecked Sendable {
    func run(
        executable: String,
        args: [String],
        in directory: String?,
        environment: [String: String]? = nil,
        timeout: Duration? = nil,
        stdoutLimitBytes: Int? = nil,
        stderrLimitBytes: Int? = nil
    ) async throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        if let directory {
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
        }

        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, newValue in
                newValue
            }
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let terminationController = ProcessTerminationController(process: process)

        return try await withTaskCancellationHandler {
            try process.run()

            async let stdoutCapture = readBoundedOutput(
                from: stdoutPipe.fileHandleForReading,
                maxBytes: stdoutLimitBytes
            )
            async let stderrCapture = readBoundedOutput(
                from: stderrPipe.fileHandleForReading,
                maxBytes: stderrLimitBytes
            )
            let didFinish = await waitForExit(of: process, timeout: timeout, terminationController: terminationController)
            let (stdout, stdoutWasTruncated) = await stdoutCapture
            let (stderr, stderrWasTruncated) = await stderrCapture

            try Task.checkCancellation()

            if !didFinish, let timeout {
                throw ShellError.timeout(executable: executable, timeout: timeout)
            }

            return ShellResult(
                stdout: String(bytes: stdout, encoding: .utf8) ?? "",
                stderr: String(bytes: stderr, encoding: .utf8) ?? "",
                exitCode: process.terminationStatus,
                stdoutWasTruncated: stdoutWasTruncated,
                stderrWasTruncated: stderrWasTruncated
            )
        } onCancel: {
            terminationController.requestTermination()
        }
    }

    private func waitForExit(
        of process: Process,
        timeout: Duration?,
        terminationController: ProcessTerminationController
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let resumption = ProcessExitResumption()
            process.terminationHandler = { _ in
                _ = resumption.resume(continuation: continuation, returning: true)
            }

            if !process.isRunning {
                _ = resumption.resume(continuation: continuation, returning: true)
                return
            }

            guard let timeout else {
                return
            }

            Task {
                try? await Task.sleep(for: timeout)
                guard resumption.resume(continuation: continuation, returning: false) else {
                    return
                }

                terminationController.requestTermination()
            }
        }
    }

    private func readBoundedOutput(from handle: FileHandle, maxBytes: Int?) async -> (Data, Bool) {
        await withTaskCancellationHandler {
            defer {
                try? handle.close()
            }

            var captured = Data()
            var wasTruncated = false

            do {
                for try await byte in handle.bytes {
                    guard let maxBytes else {
                        captured.append(byte)
                        continue
                    }

                    if captured.count < maxBytes {
                        captured.append(byte)
                    } else {
                        wasTruncated = true
                    }
                }
            } catch {
                if !Task.isCancelled {
                    print("[ShellRunner] Failed to read process output: \(error)")
                }
            }

            return (captured, wasTruncated)
        } onCancel: {
            try? handle.close()
        }
    }
}

private final class ProcessExitResumption: @unchecked Sendable {
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

private final class ProcessTerminationController: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var hasRequestedTermination = false

    init(process: Process) {
        self.process = process
    }

    func requestTermination() {
        let processIdentifier: pid_t

        lock.lock()
        guard !hasRequestedTermination else {
            lock.unlock()
            return
        }

        hasRequestedTermination = true
        guard process.isRunning else {
            lock.unlock()
            return
        }

        processIdentifier = process.processIdentifier
        process.terminate()
        lock.unlock()

        Task {
            try? await Task.sleep(for: .seconds(2))
            if process.isRunning {
                kill(processIdentifier, SIGKILL)
            }
        }
    }
}
