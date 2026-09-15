import XCTest

@testable import Alveary

final class ClaudeNativeSchedulingLaunchPolicyTests: XCTestCase {
    func testEveryClaudeLaunchDisablesNativeScheduling() {
        let arguments = ClaudeNativeSchedulingLaunchPolicy.arguments(
            harnessID: "claude",
            configuredArguments: ["--verbose"]
        )
        let environment = ClaudeNativeSchedulingLaunchPolicy.environment(
            harnessID: "claude",
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
                harnessID: "codex",
                configuredArguments: configuredArguments
            ),
            configuredArguments
        )
        XCTAssertEqual(
            ClaudeNativeSchedulingLaunchPolicy.environment(harnessID: "codex", baseEnvironment: baseEnvironment),
            baseEnvironment
        )
    }

    func testClaudeLaunchPreservesExistingDisallowedTools() {
        XCTAssertEqual(
            ClaudeNativeSchedulingLaunchPolicy.arguments(
                harnessID: "claude",
                configuredArguments: ["--disallowedTools", "Bash(git *)", "Edit", "--verbose"]
            ),
            ["--disallowedTools", "Bash(git *)", "Edit", "RemoteTrigger", "--verbose"]
        )
        XCTAssertEqual(
            ClaudeNativeSchedulingLaunchPolicy.arguments(
                harnessID: "claude",
                configuredArguments: ["--disallowed-tools=Bash,Edit"]
            ),
            ["--disallowed-tools=Bash,Edit,RemoteTrigger"]
        )
    }

    func testClaudeLaunchDoesNotDuplicateRemoteTriggerDenial() {
        let configuredArguments = ["--disallowedTools", "Bash", "RemoteTrigger", "--verbose"]

        XCTAssertEqual(
            ClaudeNativeSchedulingLaunchPolicy.arguments(
                harnessID: "claude",
                configuredArguments: configuredArguments
            ),
            configuredArguments
        )
    }
}
