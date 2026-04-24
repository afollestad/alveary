import XCTest

@testable import Alveary

extension ClaudeHookServerTests {
    static func responseBeforeTimeout(
        _ operation: @escaping @Sendable () async -> ClaudeHookHTTPResponse
    ) async throws -> ClaudeHookHTTPResponse {
        try await withThrowingTaskGroup(of: ClaudeHookHTTPResponse.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                try await Task.sleep(for: .milliseconds(500))
                throw WaitTimeoutError(description: "expected hook response before deferred handler finishes")
            }

            guard let response = try await group.next() else {
                throw WaitTimeoutError(description: "expected hook response")
            }
            group.cancelAll()
            return response
        }
    }
}
