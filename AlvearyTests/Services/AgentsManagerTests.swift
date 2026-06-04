import Foundation
import XCTest

@testable import Alveary

@MainActor
final class AgentsManagerTests: XCTestCase {
    func testDefaultAgentEnvironmentBuilderPreservesClaudeStreamWorkaroundEnvVars() {
        withEnvironmentValue(key: "CLAUDE_STREAM_IDLE_TIMEOUT_MS", value: "30000") {
            withEnvironmentValue(key: "CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK", value: "1") {
                let environment = DefaultAgentEnvironmentBuilder().buildEnvironment()

                XCTAssertEqual(environment["CLAUDE_STREAM_IDLE_TIMEOUT_MS"], "30000")
                XCTAssertEqual(environment["CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK"], "1")
            }
        }
    }
}

private func withEnvironmentValue(key: String, value: String, perform: () -> Void) {
    let previous = ProcessInfo.processInfo.environment[key]
    setenv(key, value, 1)
    defer {
        if let previous {
            setenv(key, previous, 1)
        } else {
            unsetenv(key)
        }
    }
    perform()
}
