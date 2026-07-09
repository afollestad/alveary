import Darwin
import Foundation

final class DefaultShellRunner: ShellRunner, @unchecked Sendable {
    private let additionalPathDirectories: [String]

    init(additionalPathDirectories: [String] = ExecutableSearchPath.defaultFallbackExecutableDirectories) {
        self.additionalPathDirectories = additionalPathDirectories
    }

    func run(
        executable: String,
        args: [String],
        in directory: String?,
        options: ShellRunOptions = ShellRunOptions()
    ) async throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        if let directory {
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
        }

        process.environment = processEnvironment(overriding: options.environment)

        switch options.standardInput {
        case .inherit:
            break
        case .nullDevice:
            process.standardInput = FileHandle.nullDevice
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
                maxBytes: options.stdoutLimitBytes
            )
            async let stderrCapture = readBoundedOutput(
                from: stderrPipe.fileHandleForReading,
                maxBytes: options.stderrLimitBytes
            )
            let didFinish = await waitForExit(of: process, timeout: options.timeout, terminationController: terminationController)
            let (stdout, stdoutWasTruncated) = await stdoutCapture
            let (stderr, stderrWasTruncated) = await stderrCapture

            try Task.checkCancellation()

            if !didFinish, let timeout = options.timeout {
                throw ShellError.timeout(executable: executable, timeout: timeout)
            }

            return ShellResult(
                stdout: String(bytes: stdout, encoding: .utf8) ?? "",
                stdoutData: stdout,
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
        // Drain pipes on a detached task so children with output larger than the pipe buffer
        // can keep writing while the caller waits for process exit.
        await Task.detached(priority: .utility) {
            defer {
                try? handle.close()
            }

            var captured = Data()
            var wasTruncated = false

            do {
                while true {
                    let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
                    guard !chunk.isEmpty else {
                        break
                    }

                    guard let maxBytes else {
                        captured.append(chunk)
                        continue
                    }

                    let remainingByteCount = maxBytes - captured.count
                    if remainingByteCount > 0 {
                        captured.append(contentsOf: chunk.prefix(remainingByteCount))
                    }

                    if chunk.count > remainingByteCount {
                        wasTruncated = true
                    }
                }
            } catch {
                if !Task.isCancelled {
                    print("[ShellRunner] Failed to read process output: \(error)")
                }
            }

            return (captured, wasTruncated)
        }.value
    }

    private func processEnvironment(overriding overrides: [String: String]?) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        if let overrides {
            environment.merge(overrides) { _, newValue in newValue }
        }
        environment["PATH"] = ExecutableSearchPath.augmentedPath(
            environment["PATH"],
            fallbackDirectories: additionalPathDirectories
        )
        return environment
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
