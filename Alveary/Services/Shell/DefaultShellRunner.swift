import Darwin
import Foundation

final class DefaultShellRunner: ShellRunner, @unchecked Sendable {
    private static let processGroupLauncher = "/usr/bin/perl"
    private static let processGroupLauncherProgram = """
    use POSIX qw(setpgid);
    defined(setpgid(0, 0)) or die "setpgid failed: $!";
    my $executable = shift @ARGV;
    exec {$executable} $executable, @ARGV;
    die "exec failed: $!";
    """

    private let additionalPathDirectories: [String]
    private let processTracker: (any ShellProcessTracking)?

    init(
        additionalPathDirectories: [String] = ExecutableSearchPath.defaultFallbackExecutableDirectories,
        processTracker: (any ShellProcessTracking)? = nil
    ) {
        self.additionalPathDirectories = additionalPathDirectories
        self.processTracker = processTracker
    }

    func run(
        executable: String,
        args: [String],
        in directory: String?,
        options: ShellRunOptions = ShellRunOptions()
    ) async throws -> ShellResult {
        let process = makeProcess(
            executable: executable,
            arguments: args,
            directory: directory,
            options: options
        )
        let pipes = ShellProcessPipes(process: process, options: options)
        let terminationController = ProcessTerminationController(
            process: process,
            processGroupPolicy: options.processGroupPolicy,
            ioStopController: pipes.stopController
        )
        return try await execute(
            process: process,
            executable: executable,
            options: options,
            pipes: pipes,
            terminationController: terminationController
        )
    }

    private func execute(
        process: Process,
        executable: String,
        options: ShellRunOptions,
        pipes: ShellProcessPipes,
        terminationController: ProcessTerminationController
    ) async throws -> ShellResult {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try process.run()
            terminationController.didLaunch()
            pipes.closeParentEnds()
            let processGroupID = options.processGroupPolicy == .create ? process.processIdentifier : nil
            let registered = processTracker?.register(process, processGroupID: processGroupID) ?? true
            defer {
                if registered {
                    processTracker?.unregister(process)
                }
            }
            if !registered || Task.isCancelled {
                terminationController.requestTermination()
            }
            let capture = await collect(
                process: process,
                options: options,
                pipes: pipes,
                terminationController: terminationController
            )
            guard registered else {
                throw CancellationError()
            }
            try Task.checkCancellation()
            if !capture.didFinish, let timeout = options.timeout {
                throw ShellError.timeout(executable: executable, timeout: timeout)
            }
            guard capture.inputCompleted, !capture.standardOutput.incomplete, !capture.standardError.incomplete else {
                throw ShellError.ioDrainTimedOut(executable: executable)
            }
            return ShellResult(
                stdout: String(bytes: capture.standardOutput.data, encoding: .utf8) ?? "",
                stdoutData: capture.standardOutput.data,
                stderr: String(bytes: capture.standardError.data, encoding: .utf8) ?? "",
                exitCode: process.terminationStatus,
                stdoutWasTruncated: capture.standardOutput.wasTruncated,
                stderrWasTruncated: capture.standardError.wasTruncated
            )
        } onCancel: {
            terminationController.requestTermination()
        }
    }

    private func collect(
        process: Process,
        options: ShellRunOptions,
        pipes: ShellProcessPipes,
        terminationController: ProcessTerminationController
    ) async -> ShellExecutionCapture {
        let stdinWriter = Self.writeStandardInput(
            options.standardInput,
            to: pipes.standardInput,
            stopController: pipes.stopController
        )
        async let stdoutCapture = readBoundedOutput(
            from: pipes.standardOutput.fileHandleForReading,
            maxBytes: options.stdoutLimitBytes,
            stopController: pipes.stopController
        )
        async let stderrCapture = readBoundedOutput(
            from: pipes.standardError.fileHandleForReading,
            maxBytes: options.stderrLimitBytes,
            stopController: pipes.stopController
        )
        let didFinish = await waitForExit(
            of: process,
            timeout: options.timeout,
            terminationController: terminationController
        )
        if didFinish, options.processGroupPolicy == .create {
            terminationController.requestTermination()
        }
        let inputCompleted = await stdinWriter?.value ?? true
        let standardOutput = await stdoutCapture
        let standardError = await stderrCapture
        await terminationController.awaitTermination()
        return ShellExecutionCapture(
            didFinish: didFinish,
            inputCompleted: inputCompleted,
            standardOutput: standardOutput,
            standardError: standardError
        )
    }

    private func makeProcess(
        executable: String,
        arguments: [String],
        directory: String?,
        options: ShellRunOptions
    ) -> Process {
        let process = Process()
        let launch = Self.launchConfiguration(
            executable: executable,
            arguments: arguments,
            processGroupPolicy: options.processGroupPolicy
        )
        process.executableURL = URL(fileURLWithPath: launch.executable)
        process.arguments = launch.arguments
        process.currentDirectoryURL = directory.map { URL(fileURLWithPath: $0) }
        process.environment = processEnvironment(
            overriding: options.environment,
            policy: options.environmentPolicy
        )
        return process
    }

    private static func writeStandardInput(
        _ standardInput: ShellStandardInput,
        to pipe: Pipe?,
        stopController: ShellIOStopController?
    ) -> Task<Bool, Never>? {
        guard case .text(let text) = standardInput,
              let pipe else {
            return nil
        }
        return Task.detached {
            defer { try? pipe.fileHandleForWriting.close() }
            guard let stopController else {
                do {
                    try pipe.fileHandleForWriting.write(contentsOf: Data(text.utf8))
                    return true
                } catch {
                    return true
                }
            }
            return Self.writeNonBlocking(
                Data(text.utf8),
                to: pipe.fileHandleForWriting.fileDescriptor,
                stopController: stopController
            )
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

    private func readBoundedOutput(
        from handle: FileHandle,
        maxBytes: Int?,
        stopController: ShellIOStopController?
    ) async -> ShellOutputCapture {
        // Drain pipes on a detached task so children with output larger than the pipe buffer
        // can keep writing while the caller waits for process exit.
        await Task.detached(priority: .utility) {
            defer {
                try? handle.close()
            }

            guard let stopController else {
                return Self.readBlocking(from: handle, maxBytes: maxBytes)
            }
            return Self.readNonBlocking(
                from: handle.fileDescriptor,
                maxBytes: maxBytes,
                stopController: stopController
            )
        }.value
    }

    private static func readBlocking(from handle: FileHandle, maxBytes: Int?) -> ShellOutputCapture {
        var captured = Data()
        var wasTruncated = false

        do {
            while true {
                let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
                guard !chunk.isEmpty else {
                    break
                }

                append(chunk, to: &captured, maxBytes: maxBytes, wasTruncated: &wasTruncated)
            }
        } catch {
            if !Task.isCancelled {
                print("[ShellRunner] Failed to read process output: \(error)")
            }
        }
        return ShellOutputCapture(data: captured, wasTruncated: wasTruncated, incomplete: false)
    }

    private static func readNonBlocking(
        from descriptor: Int32,
        maxBytes: Int?,
        stopController: ShellIOStopController
    ) -> ShellOutputCapture {
        var captured = Data()
        var wasTruncated = false
        guard setNonBlocking(descriptor) else {
            return ShellOutputCapture(data: captured, wasTruncated: false, incomplete: true)
        }
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            if stopController.shouldStop {
                return ShellOutputCapture(data: captured, wasTruncated: wasTruncated, incomplete: true)
            }
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count > 0 {
                append(Data(buffer.prefix(count)), to: &captured, maxBytes: maxBytes, wasTruncated: &wasTruncated)
            } else if count == 0 {
                return ShellOutputCapture(data: captured, wasTruncated: wasTruncated, incomplete: false)
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                usleep(10_000)
            } else {
                return ShellOutputCapture(data: captured, wasTruncated: wasTruncated, incomplete: true)
            }
        }
    }

    private static func writeNonBlocking(
        _ data: Data,
        to descriptor: Int32,
        stopController: ShellIOStopController
    ) -> Bool {
        guard setNonBlocking(descriptor),
              fcntl(descriptor, F_SETNOSIGPIPE, 1) == 0 else {
            return false
        }
        var offset = 0
        return data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return true
            }
            while offset < bytes.count {
                if stopController.shouldStop {
                    return false
                }
                let count = Darwin.write(descriptor, baseAddress.advanced(by: offset), bytes.count - offset)
                if count > 0 {
                    offset += count
                } else if count < 0, errno == EINTR {
                    continue
                } else if count < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                    usleep(10_000)
                } else {
                    return false
                }
            }
            return true
        }
    }

    private static func append(
        _ chunk: Data,
        to captured: inout Data,
        maxBytes: Int?,
        wasTruncated: inout Bool
    ) {
        guard let maxBytes else {
            captured.append(chunk)
            return
        }
        let remainingByteCount = maxBytes - captured.count
        if remainingByteCount > 0 {
            captured.append(contentsOf: chunk.prefix(remainingByteCount))
        }
        if chunk.count > remainingByteCount {
            wasTruncated = true
        }
    }

    private static func setNonBlocking(_ descriptor: Int32) -> Bool {
        let flags = fcntl(descriptor, F_GETFL)
        return flags >= 0 && fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0
    }

    private static func launchConfiguration(
        executable: String,
        arguments: [String],
        processGroupPolicy: ShellProcessGroupPolicy
    ) -> (executable: String, arguments: [String]) {
        guard processGroupPolicy == .create else {
            return (executable, arguments)
        }
        return (
            Self.processGroupLauncher,
            ["-e", Self.processGroupLauncherProgram, "--", executable] + arguments
        )
    }

    private func processEnvironment(
        overriding overrides: [String: String]?,
        policy: ShellEnvironmentPolicy
    ) -> [String: String] {
        var environment = policy == .inherit ? ProcessInfo.processInfo.environment : [:]
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
