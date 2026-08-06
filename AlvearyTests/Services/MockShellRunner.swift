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
    private var gate: MockShellRunnerGate?

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

    /// Holds every subsequent `run` open after it has recorded its invocation, so a
    /// test can observe a call in flight — needed to prove concurrent callers share
    /// one spawn rather than each starting their own.
    func setGate(_ gate: MockShellRunnerGate?) {
        self.gate = gate
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
        await gate?.wait()
        switch response {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}

/// Open/wait gate so a test can park a `MockShellRunner.run` call in flight.
final class MockShellRunnerGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        let shouldReturn: Bool = withLock { isOpen }
        if shouldReturn {
            return
        }
        await withCheckedContinuation { continuation in
            let resumeNow: Bool = withLock {
                if isOpen {
                    return true
                }
                continuations.append(continuation)
                return false
            }
            if resumeNow {
                continuation.resume()
            }
        }
    }

    func open() {
        let waiting: [CheckedContinuation<Void, Never>] = withLock {
            isOpen = true
            let pending = continuations
            continuations = []
            return pending
        }
        for continuation in waiting {
            continuation.resume()
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
