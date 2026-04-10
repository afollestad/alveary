import Foundation

@MainActor
final class DefaultGitHubCLIService: GitHubCLIService {
    private static let defaultVerificationURL: URL = {
        guard let url = URL(string: "https://github.com/login/device") else {
            preconditionFailure("GitHub device login URL must be valid")
        }
        return url
    }()

    private let shell: ShellRunner
    private let authExecutable: String
    private let authArguments: [String]
    private let verificationURL: URL
    private let authTimeout: Duration
    private let processFactory: @MainActor () -> Process

    private var authProcess: Process?
    private var stderrDrainTask: Task<Void, Never>?

    init(
        shell: ShellRunner,
        authExecutable: String = "/usr/bin/env",
        authArguments: [String] = ["gh", "auth", "login", "--web", "--clipboard"],
        verificationURL: URL = DefaultGitHubCLIService.defaultVerificationURL,
        authTimeout: Duration = .seconds(300),
        processFactory: @escaping @MainActor () -> Process = { Process() }
    ) {
        self.shell = shell
        self.authExecutable = authExecutable
        self.authArguments = authArguments
        self.verificationURL = verificationURL
        self.authTimeout = authTimeout
        self.processFactory = processFactory
    }

    func checkInstalled() async -> String? {
        let result = try? await shell.run(
            executable: "/usr/bin/env",
            args: ["gh", "--version"],
            timeout: .seconds(3)
        )
        guard let result, result.succeeded else {
            return nil
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isAuthenticated() async -> Bool {
        let result = try? await shell.run(
            executable: "/usr/bin/env",
            args: ["gh", "auth", "status"],
            timeout: .seconds(5)
        )
        return result?.succeeded == true
    }

    func authenticate() async throws -> GitHubDeviceCode {
        cancelAuthentication()

        let process = processFactory()
        process.executableURL = URL(fileURLWithPath: authExecutable)
        process.arguments = authArguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw GitHubError.authLaunchFailed(error.localizedDescription)
        }

        authProcess = process

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        stderrDrainTask = Task.detached {
            do {
                for try await _ in stderrHandle.bytes {}
            } catch {
                // Ignore stderr drain failures during auth.
            }
        }

        do {
            let code = try await Task.detached {
                for try await line in stdoutHandle.bytes.lines {
                    if let code = parseGitHubDeviceCode(from: line) {
                        return code
                    }
                }
                throw GitHubError.authParseFailed
            }.value

            return GitHubDeviceCode(code: code, verificationURL: verificationURL)
        } catch {
            if process.isRunning {
                process.terminate()
            }
            clearAuthenticationState(ifCurrent: process)
            throw error
        }
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

    func run(args: [String], in directory: String?) async throws -> ShellResult {
        try await shell.run(executable: "/usr/bin/env", args: ["gh"] + args, in: directory)
    }

    private func clearAuthenticationState(ifCurrent process: Process? = nil) {
        if let process {
            guard authProcess === process else {
                return
            }
        }

        stderrDrainTask?.cancel()
        stderrDrainTask = nil
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
