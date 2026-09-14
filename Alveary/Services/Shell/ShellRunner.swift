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
    let environmentPolicy: ShellEnvironmentPolicy
    let processGroupPolicy: ShellProcessGroupPolicy
    let timeout: Duration?
    let stdoutLimitBytes: Int?
    let stderrLimitBytes: Int?
    let standardInput: ShellStandardInput

    init(
        environment: [String: String]? = nil,
        environmentPolicy: ShellEnvironmentPolicy = .inherit,
        processGroupPolicy: ShellProcessGroupPolicy = .inherit,
        timeout: Duration? = nil,
        stdoutLimitBytes: Int? = nil,
        stderrLimitBytes: Int? = nil,
        standardInput: ShellStandardInput = .inherit
    ) {
        self.environment = environment
        self.environmentPolicy = environmentPolicy
        self.processGroupPolicy = processGroupPolicy
        self.timeout = timeout
        self.stdoutLimitBytes = stdoutLimitBytes
        self.stderrLimitBytes = stderrLimitBytes
        self.standardInput = standardInput
    }
}

enum ShellEnvironmentPolicy: Sendable, Equatable {
    case inherit
    case replace
}

enum ShellProcessGroupPolicy: Sendable, Equatable {
    case inherit
    case create
}

enum ShellStandardInput: Sendable, Equatable {
    case inherit
    case nullDevice
    case text(String)
}

protocol ShellProcessTracking: Sendable {
    /// Returns false when the process was launched after its owning work was cancelled.
    func register(_ process: Process, processGroupID: Int32?) -> Bool
    func unregister(_ process: Process)
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
        environmentPolicy: ShellEnvironmentPolicy = .inherit,
        processGroupPolicy: ShellProcessGroupPolicy = .inherit,
        timeout: Duration? = nil,
        stdoutLimitBytes: Int? = nil,
        stderrLimitBytes: Int? = nil,
        standardInput: ShellStandardInput = .inherit
    ) async throws -> ShellResult {
        try await run(
            executable: executable,
            args: args,
            in: directory,
            options: ShellRunOptions(
                environment: environment,
                environmentPolicy: environmentPolicy,
                processGroupPolicy: processGroupPolicy,
                timeout: timeout,
                stdoutLimitBytes: stdoutLimitBytes,
                stderrLimitBytes: stderrLimitBytes,
                standardInput: standardInput
            )
        )
    }
}

enum ShellError: Error, Sendable, Equatable {
    case timeout(executable: String, timeout: Duration)
    case ioFailure(ShellIOFailure)
    case invalidDirectory(String)
}

enum ShellOutputFailure: Sendable, Equatable {
    case drainTimedOut
    case readFailed(Int32)
}

/// Retains incomplete captures for callers with a separate authoritative result; stdout is never a diagnostic.
struct ShellIOFailure: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let executable: String
    let result: ShellResult
    let exitedNormally: Bool
    let inputCompleted: Bool
    let stdoutFailure: ShellOutputFailure?
    let stderrFailure: ShellOutputFailure?

    var description: String { diagnostic }
    var debugDescription: String { diagnostic }

    fileprivate var diagnostic: String {
        let exit = exitedNormally ? "exited with code \(result.exitCode)" : "was terminated by signal \(result.exitCode)"
        var reasons: [String] = []
        if !inputCompleted { reasons.append("standard input was not fully delivered") }
        if let stdoutFailure { reasons.append(Self.describe(stdoutFailure, stream: "stdout")) }
        if let stderrFailure { reasons.append(Self.describe(stderrFailure, stream: "stderr")) }
        let message = "\(executable) \(exit), but \(reasons.joined(separator: "; "))."
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stderr.isEmpty else { return message }
        var bytes = Data(stderr.utf8.prefix(2_000))
        while !bytes.isEmpty, String(data: bytes, encoding: .utf8) == nil { bytes.removeLast() }
        let suffix = stderr.utf8.count > bytes.count || result.stderrWasTruncated ? "…" : ""
        return message + " Stderr: " + (String(data: bytes, encoding: .utf8) ?? "") + suffix
    }

    private static func describe(_ failure: ShellOutputFailure, stream: String) -> String {
        switch failure {
        case .drainTimedOut: "\(stream) did not close before the I/O deadline"
        case .readFailed(let code): "\(stream) could not be read (errno \(code))"
        }
    }
}

extension ShellError: LocalizedError, CustomStringConvertible, CustomDebugStringConvertible {
    var description: String { errorDescription ?? "The command failed." }
    var debugDescription: String { description }

    var errorDescription: String? {
        switch self {
        case .invalidDirectory(let directory):
            return "The working directory is unavailable: \(directory)"
        case .timeout(let executable, let timeout):
            return "\(executable) timed out after \(timeout.components.seconds) seconds"
        case .ioFailure(let failure):
            return failure.diagnostic
        }
    }
}
