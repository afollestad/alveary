import Foundation

struct ShellResult: Sendable, Equatable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let stdoutWasTruncated: Bool
    let stderrWasTruncated: Bool

    var succeeded: Bool {
        exitCode == 0
    }
}

protocol ShellRunner: Sendable {
    func run(
        executable: String,
        args: [String],
        in directory: String?,
        environment: [String: String]?,
        timeout: Duration?,
        stdoutLimitBytes: Int?,
        stderrLimitBytes: Int?
    ) async throws -> ShellResult
}

extension ShellRunner {
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
            environment: environment,
            timeout: timeout,
            stdoutLimitBytes: stdoutLimitBytes,
            stderrLimitBytes: stderrLimitBytes
        )
    }
}

enum ShellError: Error, Sendable, Equatable {
    case timeout(executable: String, timeout: Duration)
}
