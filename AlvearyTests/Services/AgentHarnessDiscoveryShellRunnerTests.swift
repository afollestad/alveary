import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

final class AgentHarnessDiscoveryShellRunnerTests: XCTestCase {
    func testDiscoveryBoundsCommandsWithoutChangingTheGeneralSDKRunner() async throws {
        let shell = DiscoveryRecordingShellRunner()
        let command = AgentCLIKit.ShellCommand(
            executable: "/test/provider",
            arguments: ["--version"],
            environment: ["DISCOVERY_TEST": "value"],
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        let result = try await AgentHarnessDiscoveryShellRunner(shellRunner: shell).run(command)
        _ = try await AgentCLIKitShellRunnerAdapter(shellRunner: shell).run(command)

        let calls = await shell.calls
        XCTAssertEqual(calls.count, 2)
        let discovery = try XCTUnwrap(calls.first)
        XCTAssertEqual(discovery.executable, command.executable)
        XCTAssertEqual(discovery.arguments, command.arguments)
        XCTAssertEqual(discovery.directory, command.workingDirectory?.path)
        XCTAssertEqual(discovery.options.environment, command.environment)
        XCTAssertEqual(discovery.options.environmentPolicy, .inherit)
        XCTAssertEqual(discovery.options.processGroupPolicy, .create)
        XCTAssertEqual(discovery.options.timeout, .seconds(5))
        XCTAssertEqual(discovery.options.stdoutLimitBytes, 256 * 1024)
        XCTAssertEqual(discovery.options.stderrLimitBytes, 256 * 1024)
        XCTAssertEqual(discovery.options.standardInput, .nullDevice)
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertEqual(result.stdout, "version output")
        XCTAssertEqual(result.stderr, "diagnostic")

        let general = try XCTUnwrap(calls.last)
        XCTAssertNil(general.options.timeout)
        XCTAssertEqual(general.options.processGroupPolicy, .inherit)
        XCTAssertEqual(general.options.standardInput, .inherit)
    }

    func testDiscoveryRejectsOversizedOutputInsteadOfParsingATruncatedResult() async throws {
        let runner = AgentHarnessDiscoveryShellRunner(shellRunner: DefaultShellRunner())
        for script in ["print 'A' x 300000;", "print STDERR 'A' x 300000;"] {
            do {
                _ = try await runner.run(.init(executable: "/usr/bin/perl", arguments: ["-e", script]))
                XCTFail("Expected oversized discovery output to be rejected")
            } catch {
                XCTAssertTrue(error is AgentHarnessDiscoveryShellError)
            }
        }
    }

    func testTimedOutDiscoveryCleansUpDescendantsAndTheNextProbeCanRun() async throws {
        let registry = PullRequestReviewWorkerProcessRegistry()
        let tracker = registry.tracker(for: .init(runID: "discovery-test", generation: 0, executionID: "probe"))
        let runner = AgentHarnessDiscoveryShellRunner(
            shellRunner: DefaultShellRunner(processTracker: tracker),
            timeout: .seconds(1)
        )
        let script = #"$SIG{TERM}=sub{}; my $pid = fork(); die 'fork failed' unless defined $pid; while (1) { sleep 10; }"#
        let clock = ContinuousClock()
        let startedAt = clock.now

        do {
            _ = try await runner.run(.init(executable: "/usr/bin/perl", arguments: ["-e", script]))
            XCTFail("Expected the stalled discovery command to time out")
        } catch let ShellError.timeout(executable, timeout) {
            XCTAssertEqual(executable, "/usr/bin/perl")
            XCTAssertEqual(timeout, .seconds(1))
            XCTAssertLessThan(startedAt.duration(to: clock.now), .seconds(4))
        }
        XCTAssertFalse(registry.hasLiveProcesses)

        let result = try await runner.run(.init(executable: "/usr/bin/printf", arguments: ["ready"]))
        XCTAssertEqual(result.stdout, "ready")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testClaudeAuthDiscoveryRecoversAfterAStalledCLIWithoutLeavingDescendants() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("claude")
        try writeClaudeFixture(executable, isReady: false)
        let registry = PullRequestReviewWorkerProcessRegistry()
        let tracker = registry.tracker(for: .init(runID: "auth-discovery-test", generation: 0, executionID: "probe"))
        let runner = AgentHarnessDiscoveryShellRunner(
            shellRunner: DefaultShellRunner(processTracker: tracker),
            timeout: .seconds(1)
        )
        let resolver = AgentCLIKit.DefaultAgentHarnessExecutableResolver(detector: .init(shellRunner: runner))
        let definition = AgentCLIKit.AgentHarnessDefinition(
            id: .claude, displayName: "Test Claude", executableNames: [executable.path]
        )
        let probe = AgentCLIKit.ClaudeAuthProbe(shellRunner: runner, environment: [:], executablePath: {
            await resolver.resolvedExecutablePath(for: definition)
        })
        let clock = ContinuousClock()
        let startedAt = clock.now

        let timedOut = await probe.readiness()

        XCTAssertEqual(timedOut.state, .unknown)
        XCTAssertTrue(FileManager.default.fileExists(atPath: executable.path + ".started"), "The auth command must reach its stall")
        XCTAssertLessThan(startedAt.duration(to: clock.now), .seconds(4))
        XCTAssertFalse(registry.hasLiveProcesses)
        try writeClaudeFixture(executable, isReady: true)

        let repaired = await probe.readiness()

        XCTAssertEqual(repaired.state, .ready, repaired.diagnostics.joined(separator: "; "))
        XCTAssertEqual(repaired.credentialSource, .cliAuthStatus)
        XCTAssertFalse(registry.hasLiveProcesses)
    }

    private func writeClaudeFixture(_ executable: URL, isReady: Bool) throws {
        let auth = isReady
            ? #"print '{"loggedIn":true,"authMethod":"claude.ai"}';"#
            : #"$SIG{TERM}=sub{}; my $pid = fork(); die 'fork failed' unless defined $pid; while (1) { sleep 10; }"#
        try """
        #!/usr/bin/perl
        if ($ARGV[0] eq '--version') { print '1.0.0'; exit; }
        open my $started, '>', "$0.started" or die $!;
        close $started;
        \(auth)
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }
}

private actor DiscoveryRecordingShellRunner: ShellRunner {
    struct Call: Sendable {
        let executable: String
        let arguments: [String]
        let directory: String?
        let options: ShellRunOptions
    }

    private(set) var calls: [Call] = []

    func run(executable: String, args: [String], in directory: String?, options: ShellRunOptions) async throws -> ShellResult {
        calls.append(Call(executable: executable, arguments: args, directory: directory, options: options))
        return ShellResult(stdout: "version output", stderr: "diagnostic", exitCode: 7, stdoutWasTruncated: false, stderrWasTruncated: false)
    }
}
