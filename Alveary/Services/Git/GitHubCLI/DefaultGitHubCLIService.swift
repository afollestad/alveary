import Foundation

@MainActor
final class DefaultGitHubCLIService: GitHubCLIService {
    private static let defaultAuthArguments = ["auth", "login", "--web", "--clipboard"]

    private static let defaultVerificationURL: URL = {
        guard let url = URL(string: "https://github.com/login/device") else {
            preconditionFailure("GitHub device login URL must be valid")
        }
        return url
    }()

    private let shell: ShellRunner
    private let executableResolver: any ExecutablePathResolving
    private let verificationURL: URL
    private let authTimeout: Duration
    private let processFactory: @MainActor () -> Process

    private var authProcess: Process?
    /// Kept for the flow's lifetime: it goes on draining both pipes after the code arrives, so a
    /// full pipe can never block `gh` mid-poll.
    private var outputReader: DeviceFlowOutputReader?

    init(
        shell: ShellRunner,
        executableResolver: (any ExecutablePathResolving)? = nil,
        verificationURL: URL = DefaultGitHubCLIService.defaultVerificationURL,
        authTimeout: Duration = .seconds(300),
        processFactory: @escaping @MainActor () -> Process = { Process() }
    ) {
        self.shell = shell
        self.executableResolver = executableResolver ?? DefaultExecutablePathResolver(shell: shell)
        self.verificationURL = verificationURL
        self.authTimeout = authTimeout
        self.processFactory = processFactory
    }

    func checkInstalled() async -> String? {
        guard let ghExecutable = await executableResolver.resolveExecutablePath(for: "gh") else {
            return nil
        }

        let result = try? await shell.run(
            executable: ghExecutable,
            args: ["--version"],
            timeout: .seconds(3)
        )
        guard let result, result.succeeded else {
            return nil
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isAuthenticated() async -> Bool {
        guard let ghExecutable = await executableResolver.resolveExecutablePath(for: "gh") else {
            return false
        }

        let result = try? await shell.run(
            executable: ghExecutable,
            args: ["auth", "status"],
            timeout: .seconds(5)
        )
        return result?.succeeded == true
    }

    func authenticate() async throws -> GitHubDeviceCode {
        try await startDeviceFlow(arguments: Self.defaultAuthArguments)
    }

    /// `-h` is required: without a TTY, `gh auth refresh` refuses to pick a host itself.
    func refreshAuthentication(addingScopes scopes: [String]) async throws -> GitHubDeviceCode {
        try await startDeviceFlow(arguments: ["auth", "refresh", "-h", "github.com", "-s", scopes.joined(separator: ","), "--clipboard"])
    }

    /// Launches a device-code flow and returns once `gh` prints its one-time code, leaving the
    /// process polling GitHub for `awaitAuthentication()` to wait on.
    ///
    /// Both streams are scanned, because `gh` 2.103 prints the code to stderr for `auth login`
    /// and `auth refresh` alike. `DeviceFlowOutputReader` owns how they are read.
    private func startDeviceFlow(arguments: [String]) async throws -> GitHubDeviceCode {
        cancelAuthentication()

        guard let ghExecutable = await executableResolver.resolveExecutablePath(for: "gh") else {
            throw GitHubError.authLaunchFailed("GitHub CLI is not installed.")
        }
        let process = processFactory()
        process.executableURL = URL(fileURLWithPath: ghExecutable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        // Reading starts before launch so no early output can slip past the handlers.
        let reader = DeviceFlowOutputReader(handles: [stdoutPipe.fileHandleForReading, stderrPipe.fileHandleForReading])

        do {
            try process.run()
        } catch {
            reader.stop()
            throw GitHubError.authLaunchFailed(error.localizedDescription)
        }

        authProcess = process
        outputReader = reader

        for await line in reader.lines {
            if let code = parseGitHubDeviceCode(from: line) {
                return GitHubDeviceCode(code: code, verificationURL: verificationURL)
            }
        }

        // Both streams closed without a code — `gh` exited — or the caller was cancelled.
        if process.isRunning {
            process.terminate()
        }
        clearAuthenticationState(ifCurrent: process)
        try Task.checkCancellation()
        throw GitHubError.authParseFailed
    }

    func awaitAuthentication() async throws -> Bool {
        guard let process = authProcess else {
            return false
        }

        let didAuthenticate = await withCheckedContinuation { continuation in
            let resumption = AuthContinuationResumption()

            process.terminationHandler = { terminatedProcess in
                _ = resumption.resume(
                    continuation: continuation,
                    returning: terminatedProcess.terminationStatus == 0
                )
            }

            if !process.isRunning {
                _ = resumption.resume(
                    continuation: continuation,
                    returning: process.terminationStatus == 0
                )
            }

            Task {
                try? await Task.sleep(for: authTimeout)
                guard resumption.resume(continuation: continuation, returning: false) else {
                    return
                }
                if process.isRunning {
                    process.terminate()
                }
            }
        }

        if authProcess === process {
            clearAuthenticationState(ifCurrent: process)
        }
        return didAuthenticate
    }

    func cancelAuthentication() {
        guard let process = authProcess else {
            return
        }
        if process.isRunning {
            process.terminate()
        }
        clearAuthenticationState(ifCurrent: process)
    }

    private func clearAuthenticationState(ifCurrent process: Process? = nil) {
        if let process {
            guard authProcess === process else {
                return
            }
        }

        outputReader?.stop()
        outputReader = nil
        authProcess = nil
    }
}

private final class AuthContinuationResumption: @unchecked Sendable {
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

/// Splits a device flow's stdout and stderr into lines as they arrive, through
/// `readabilityHandler`. Not `FileHandle.bytes`: on a pipe from a live `gh` it delivered nothing
/// until the process exited — the one-time code, printed within two seconds, surfaced only when
/// `gh` was killed twelve seconds later — which left the sign-in sheets waiting on a code `gh`
/// had already printed.
private final class DeviceFlowOutputReader: @unchecked Sendable {
    let lines: AsyncStream<String>

    private let continuation: AsyncStream<String>.Continuation
    private let handles: [FileHandle]
    private let lock = NSLock()
    private var buffers: [ObjectIdentifier: Data] = [:]
    private var openHandleCount: Int

    init(handles: [FileHandle]) {
        (lines, continuation) = AsyncStream.makeStream(of: String.self)
        self.handles = handles
        openHandleCount = handles.count
        for handle in handles {
            handle.readabilityHandler = { [weak self] handle in
                self?.consume(handle.availableData, from: handle)
            }
        }
    }

    /// Detaches the handlers and ends `lines`; for teardown once `gh` has been stopped.
    func stop() {
        for handle in handles {
            handle.readabilityHandler = nil
        }
        continuation.finish()
    }

    /// Empty data is end of file: that pipe is done, and `lines` ends once both are.
    private func consume(_ data: Data, from handle: FileHandle) {
        lock.lock()
        defer { lock.unlock() }
        let key = ObjectIdentifier(handle)
        guard !data.isEmpty else {
            handle.readabilityHandler = nil
            if let remainder = buffers.removeValue(forKey: key) {
                yieldLine(remainder)
            }
            openHandleCount -= 1
            if openHandleCount == 0 {
                continuation.finish()
            }
            return
        }
        var buffer = (buffers[key] ?? Data()) + data
        while let newline = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            yieldLine(buffer[buffer.startIndex..<newline])
            buffer = buffer[buffer.index(after: newline)...]
        }
        buffers[key] = buffer
    }

    /// A line that is not UTF-8 cannot hold the code, so it is dropped rather than repaired.
    private func yieldLine(_ bytes: Data) {
        guard !bytes.isEmpty, let line = String(bytes: bytes, encoding: .utf8) else {
            return
        }
        continuation.yield(line)
    }
}

private func parseGitHubDeviceCode(from line: String) -> String? {
    let prefix = "One-time code ("
    guard let prefixRange = line.range(of: prefix) else {
        return nil
    }

    let codeStart = prefixRange.upperBound
    guard let codeEnd = line[codeStart...].firstIndex(of: ")") else {
        return nil
    }

    let code = line[codeStart..<codeEnd]
    return code.isEmpty ? nil : String(code)
}
