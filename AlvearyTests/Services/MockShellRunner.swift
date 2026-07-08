import Foundation

@testable import Alveary

actor MockShellRunner: ShellRunner {
    struct Invocation: Sendable, Equatable {
        let executable: String
        let args: [String]
        let directory: String?
        let environment: [String: String]?
        let timeout: Duration?
        let stdoutLimitBytes: Int?
        let stderrLimitBytes: Int?
        let standardInput: ShellStandardInput
    }

    enum Response: Sendable, Equatable {
        case success(ShellResult)
        case failure(MockShellRunnerError)
    }

    enum MockShellRunnerError: Error, Sendable, Equatable {
        case message(String)
    }

    private let defaultResponse: Response
    private(set) var invocations: [Invocation]
    private var queuedResponses: [Response]

    init(
        defaultResponse: Response = .success(
            ShellResult(stdout: "", stderr: "", exitCode: 0, stdoutWasTruncated: false, stderrWasTruncated: false)
        )
    ) {
        self.defaultResponse = defaultResponse
        self.invocations = []
        self.queuedResponses = []
    }

    func enqueue(_ response: Response) {
        queuedResponses.append(response)
    }

    func run(
        executable: String,
        args: [String],
        in directory: String?,
        options: ShellRunOptions
    ) async throws -> ShellResult {
        invocations.append(
            Invocation(
                executable: executable,
                args: args,
                directory: directory,
                environment: options.environment,
                timeout: options.timeout,
                stdoutLimitBytes: options.stdoutLimitBytes,
                stderrLimitBytes: options.stderrLimitBytes,
                standardInput: options.standardInput
            )
        )

        let response = queuedResponses.isEmpty ? defaultResponse : queuedResponses.removeFirst()
        switch response {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}
