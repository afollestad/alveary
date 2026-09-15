import Foundation
import XCTest

@testable import Alveary

extension PullRequestReviewWorkerExecutorTests {
    func testOnlyCodexExecutionRecoversACompleteTurnFromAnIODrainFailure() async throws {
        let stream = try ReviewWorkerIOTestSupport.codexStream(finalText: "{\"findings\":[]}")
        for harnessID in ["codex", "claude"] {
            let capabilities = ReviewWorkerIOTestShellRunner(outcomes: [.help])
            let execution = ReviewWorkerIOTestShellRunner(outcomes: [.ioFailure(stream)])
            let fixture = try await makeFixture(
                harnessID: harnessID, script: "#!/bin/sh\nexit 99\n",
                capabilityShellRunner: capabilities, executionShellRunner: execution
            )
            do {
                let output = try await executeIOFixture(fixture)
                XCTAssertEqual(harnessID, "codex", "Claude must retain the I/O failure.")
                XCTAssertEqual(output, "{\"findings\":[]}")
            } catch let error as ShellError {
                XCTAssertEqual(harnessID, "claude", "A completed Codex turn should be recoverable.")
                XCTAssertEqual(error, ReviewWorkerIOTestSupport.failure(executable: fixture.configuration.executablePath, stdout: stream))
            }
            let prompts = await execution.prompts
            XCTAssertEqual(prompts, ["Review the packet"])
            XCTAssertFalse(fixture.registry.hasLiveProcesses)
        }
    }

    func testCapabilityChecksNeverRecoverAnIODrainFailure() async throws {
        let stream = try ReviewWorkerIOTestSupport.codexStream(finalText: ReviewWorkerIOTestSupport.help)
        let capabilities = ReviewWorkerIOTestShellRunner(outcomes: [.ioFailure(stream)])
        let execution = ReviewWorkerIOTestShellRunner(outcomes: [.ioFailure(stream)])
        let fixture = try await makeFixture(
            harnessID: "codex", script: "#!/bin/sh\nexit 99\n",
            capabilityShellRunner: capabilities, executionShellRunner: execution
        )

        do {
            _ = try await executeIOFixture(fixture)
            XCTFail("Expected strict capability failure")
        } catch let error as ShellError {
            XCTAssertEqual(error, ReviewWorkerIOTestSupport.failure(executable: fixture.configuration.executablePath, stdout: stream))
        }
        let executionCalls = await execution.callCount
        XCTAssertEqual(executionCalls, 0)
    }

    func testCodexMessageWithoutTurnCompletionRetainsTheOriginalIOFailure() async throws {
        let stream = """
        {"type":"turn.started"}
        {"type":"item.completed","item":{"id":"answer","type":"agent_message","text":"Unconfirmed final output"}}

        """
        let fixture = try await makeFixture(
            harnessID: "codex", script: "#!/bin/sh\nexit 99\n",
            capabilityShellRunner: ReviewWorkerIOTestShellRunner(outcomes: [.help]),
            executionShellRunner: ReviewWorkerIOTestShellRunner(outcomes: [.ioFailure(stream)])
        )

        do {
            _ = try await executeIOFixture(fixture)
            XCTFail("Expected the original I/O failure without a completed turn")
        } catch let error as ShellError {
            XCTAssertEqual(error, ReviewWorkerIOTestSupport.failure(executable: fixture.configuration.executablePath, stdout: stream))
        }
    }

    func testExecutionTimeoutRemainsAFailure() async throws {
        let fixture = try await makeFixture(
            harnessID: "codex", script: "#!/bin/sh\nexit 99\n",
            capabilityShellRunner: ReviewWorkerIOTestShellRunner(outcomes: [.help]),
            executionShellRunner: ReviewWorkerIOTestShellRunner(outcomes: [.timeout])
        )

        do {
            _ = try await executeIOFixture(fixture)
            XCTFail("Expected timeout")
        } catch let error as ShellError {
            XCTAssertEqual(error, .timeout(executable: fixture.configuration.executablePath, timeout: .seconds(1)))
        }
    }

    func testCancellationWinsOverARecoverableCompletedTurn() async throws {
        let stream = try ReviewWorkerIOTestSupport.codexStream(finalText: "{\"findings\":[]}")
        let fixture = try await makeFixture(
            harnessID: "codex", script: "#!/bin/sh\nexit 99\n",
            capabilityShellRunner: ReviewWorkerIOTestShellRunner(outcomes: [.help]),
            executionShellRunner: ReviewWorkerIOTestShellRunner(outcomes: [.cancelledIOFailure(stream)])
        )

        do {
            _ = try await executeIOFixture(fixture)
            XCTFail("Expected cancellation instead of recovered output")
        } catch is CancellationError {
            XCTAssertFalse(fixture.registry.hasLiveProcesses)
        }
    }

    private func executeIOFixture(_ fixture: Fixture) async throws -> String {
        try await fixture.executor.execute(
            configuration: fixture.configuration, packet: fixture.packet, prompt: "Review the packet",
            runID: fixture.packet.runID, generation: 1, executionID: "io-recovery"
        )
    }
}

enum ReviewWorkerIOTestSupport {
    static let help = """
    --ephemeral --ignore-user-config --ignore-rules --skip-git-repo-check --strict-config --disable --sandbox
    --safe-mode --no-session-persistence --restricted --strict-mcp-config --permission-mode dontAsk
    --permission-prompts --tools --disable-slash-commands --no-chrome
    """

    static func codexStream(finalText: String) throws -> String {
        let encoded = try ReviewTeamDigest.jsonString(finalText)
        return """
        {"type":"thread.started","thread_id":"review-thread"}
        {"type":"turn.started"}
        {"type":"item.completed","item":{"id":"answer","type":"agent_message","text":\(encoded)}}
        {"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1}}

        """
    }

    static func failure(executable: String, stdout: String) -> ShellError {
        .ioFailure(ShellIOFailure(
            executable: executable,
            result: ShellResult(stdout: stdout, stderr: "", exitCode: 0, stdoutWasTruncated: false, stderrWasTruncated: false),
            exitedNormally: true, inputCompleted: true, stdoutFailure: nil, stderrFailure: .drainTimedOut
        ))
    }
}

actor ReviewWorkerIOTestShellRunner: ShellRunner {
    enum Outcome: Sendable {
        case help
        case ioFailure(String)
        case timeout
        case cancelledIOFailure(String)
    }

    private var outcomes: [Outcome]
    private(set) var callCount = 0
    private(set) var prompts: [String] = []

    init(outcomes: [Outcome]) { self.outcomes = outcomes }

    func run(executable: String, args: [String], in directory: String?, options: ShellRunOptions) async throws -> ShellResult {
        callCount += 1
        if case .text(let prompt) = options.standardInput { prompts.append(prompt) }
        guard let outcome = outcomes.first else { throw ShellError.invalidDirectory("No test shell response was configured.") }
        if outcomes.count > 1 { outcomes.removeFirst() }
        switch outcome {
        case .help:
            return ShellResult(stdout: ReviewWorkerIOTestSupport.help, stderr: "", exitCode: 0,
                               stdoutWasTruncated: false, stderrWasTruncated: false)
        case .ioFailure(let stdout):
            throw ReviewWorkerIOTestSupport.failure(executable: executable, stdout: stdout)
        case .timeout:
            throw ShellError.timeout(executable: executable, timeout: .seconds(1))
        case .cancelledIOFailure(let stdout):
            withUnsafeCurrentTask { $0?.cancel() }
            throw ReviewWorkerIOTestSupport.failure(executable: executable, stdout: stdout)
        }
    }
}
