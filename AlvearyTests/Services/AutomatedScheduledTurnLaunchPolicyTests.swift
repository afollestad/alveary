import XCTest

@testable import Alveary

final class AutomatedScheduledTurnLaunchPolicyTests: XCTestCase {
    func testClaudeAutomatedTurnDisablesNativeScheduling() {
        let arguments = AutomatedScheduledTurnLaunchPolicy.arguments(
            providerID: "claude",
            configuredArguments: ["--verbose"],
            isAutomatedScheduledTurn: true
        )
        let environment = AutomatedScheduledTurnLaunchPolicy.environment(
            providerID: "claude",
            baseEnvironment: ["PATH": "/usr/bin"],
            isAutomatedScheduledTurn: true
        )

        XCTAssertEqual(arguments, ["--verbose", "--disallowedTools", "RemoteTrigger"])
        XCTAssertEqual(environment["PATH"], "/usr/bin")
        XCTAssertEqual(environment["CLAUDE_CODE_DISABLE_CRON"], "1")
    }

    func testOrdinaryAndNonClaudeTurnsRemainUnchanged() {
        let configuredArguments = ["--verbose"]
        let baseEnvironment = ["PATH": "/usr/bin"]

        XCTAssertEqual(
            AutomatedScheduledTurnLaunchPolicy.arguments(
                providerID: "claude",
                configuredArguments: configuredArguments,
                isAutomatedScheduledTurn: false
            ),
            configuredArguments
        )
        XCTAssertEqual(
            AutomatedScheduledTurnLaunchPolicy.environment(
                providerID: "codex",
                baseEnvironment: baseEnvironment,
                isAutomatedScheduledTurn: true
            ),
            baseEnvironment
        )
    }

    func testClaudeAutomatedTurnPreservesExistingDisallowedTools() {
        XCTAssertEqual(
            AutomatedScheduledTurnLaunchPolicy.arguments(
                providerID: "claude",
                configuredArguments: ["--disallowedTools", "Bash(git *)", "Edit", "--verbose"],
                isAutomatedScheduledTurn: true
            ),
            ["--disallowedTools", "Bash(git *)", "Edit", "RemoteTrigger", "--verbose"]
        )
        XCTAssertEqual(
            AutomatedScheduledTurnLaunchPolicy.arguments(
                providerID: "claude",
                configuredArguments: ["--disallowed-tools=Bash,Edit"],
                isAutomatedScheduledTurn: true
            ),
            ["--disallowed-tools=Bash,Edit,RemoteTrigger"]
        )
    }

    func testClaudeAutomatedTurnDoesNotDuplicateRemoteTriggerDenial() {
        let configuredArguments = ["--disallowedTools", "Bash", "RemoteTrigger", "--verbose"]

        XCTAssertEqual(
            AutomatedScheduledTurnLaunchPolicy.arguments(
                providerID: "claude",
                configuredArguments: configuredArguments,
                isAutomatedScheduledTurn: true
            ),
            configuredArguments
        )
    }
}
