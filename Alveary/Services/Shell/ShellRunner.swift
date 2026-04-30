import Foundation

struct ShellResult: Sendable, Equatable {
    let stdout: String
    let stdoutData: Data
    let stderr: String
    let exitCode: Int32
    let stdoutWasTruncated: Bool
    let stderrWasTruncated: Bool

    init(
        stdout: String,
        stdoutData: Data? = nil,
        stderr: String,
        exitCode: Int32,
        stdoutWasTruncated: Bool,
        stderrWasTruncated: Bool
    ) {
        self.stdout = stdout
        self.stdoutData = stdoutData ?? Data(stdout.utf8)
        self.stderr = stderr
        self.exitCode = exitCode
        self.stdoutWasTruncated = stdoutWasTruncated
        self.stderrWasTruncated = stderrWasTruncated
    }

    var succeeded: Bool {
        exitCode == 0
    }
}

struct ShellRunOptions: Sendable, Equatable {
    let environment: [String: String]?
    let timeout: Duration?
    let stdoutLimitBytes: Int?
    let stderrLimitBytes: Int?

    init(
        environment: [String: String]? = nil,
        timeout: Duration? = nil,
        stdoutLimitBytes: Int? = nil,
        stderrLimitBytes: Int? = nil
    ) {
        self.environment = environment
        self.timeout = timeout
        self.stdoutLimitBytes = stdoutLimitBytes
        self.stderrLimitBytes = stderrLimitBytes
    }
}

protocol ShellRunner: Sendable {
    func run(
        executable: String,
        args: [String],
        in directory: String?,
        options: ShellRunOptions
    ) async throws -> ShellResult
}

extension ShellRunner {
    func run(
        executable: String,
        args: [String],
        in directory: String? = nil,
        options: ShellRunOptions = ShellRunOptions()
    ) async throws -> ShellResult {
        try await run(
            executable: executable,
            args: args,
            in: directory,
            options: options
        )
    }

    func run(
        executable: String,
        args: [String],
        in directory: String? = nil,
        environment: [String: String]? = nil,
        timeout: Duration? = nil,
        stdoutLimitBytes: Int? = nil,
        stderrLimitBytes: Int? = nil
    ) async throws -> ShellResult {
        try await run(
            executable: executable,
            args: args,
            in: directory,
            options: ShellRunOptions(
                environment: environment,
                timeout: timeout,
                stdoutLimitBytes: stdoutLimitBytes,
                stderrLimitBytes: stderrLimitBytes
            )
        )
    }
}

enum ShellError: Error, Sendable, Equatable {
    case timeout(executable: String, timeout: Duration)
}

extension ShellError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .timeout(let executable, let timeout):
            return "\(executable) timed out after \(timeout.components.seconds) seconds"
        }
    }
}
