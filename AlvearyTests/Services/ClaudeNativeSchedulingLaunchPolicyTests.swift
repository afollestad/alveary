import XCTest

@testable import Alveary

final class ClaudeNativeSchedulingLaunchPolicyTests: XCTestCase {
    func testEveryClaudeLaunchDisablesNativeScheduling() {
        let arguments = ClaudeNativeSchedulingLaunchPolicy.arguments(
            providerID: "claude",
            configuredArguments: ["--verbose"]
        )
        let environment = ClaudeNativeSchedulingLaunchPolicy.environment(
            providerID: "claude",
            baseEnvironment: ["PATH": "/usr/bin"]
        )

        XCTAssertEqual(arguments, ["--verbose", "--disallowedTools", "RemoteTrigger"])
        XCTAssertEqual(environment["PATH"], "/usr/bin")
        XCTAssertEqual(environment["CLAUDE_CODE_DISABLE_CRON"], "1")
    }

    func testNonClaudeLaunchesRemainUnchanged() {
        let configuredArguments = ["--verbose"]
        let baseEnvironment = ["PATH": "/usr/bin"]

        XCTAssertEqual(
            ClaudeNativeSchedulingLaunchPolicy.arguments(
                providerID: "codex",
                configuredArguments: configuredArguments
            ),
            configuredArguments
        )
        XCTAssertEqual(
            ClaudeNativeSchedulingLaunchPolicy.environment(providerID: "codex", baseEnvironment: baseEnvironment),
            baseEnvironment
        )
    }

    func testClaudeLaunchPreservesExistingDisallowedTools() {
        XCTAssertEqual(
            ClaudeNativeSchedulingLaunchPolicy.arguments(
                providerID: "claude",
                configuredArguments: ["--disallowedTools", "Bash(git *)", "Edit", "--verbose"]
            ),
            ["--disallowedTools", "Bash(git *)", "Edit", "RemoteTrigger", "--verbose"]
        )
        XCTAssertEqual(
            ClaudeNativeSchedulingLaunchPolicy.arguments(
                providerID: "claude",
                configuredArguments: ["--disallowed-tools=Bash,Edit"]
            ),
            ["--disallowed-tools=Bash,Edit,RemoteTrigger"]
        )
    }

    func testClaudeLaunchDoesNotDuplicateRemoteTriggerDenial() {
        let configuredArguments = ["--disallowedTools", "Bash", "RemoteTrigger", "--verbose"]

        XCTAssertEqual(
            ClaudeNativeSchedulingLaunchPolicy.arguments(
                providerID: "claude",
                configuredArguments: configuredArguments
            ),
            configuredArguments
        )
    }
}
