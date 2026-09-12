import Foundation
import XCTest

@testable import Alveary

final class PullRequestReviewWorkerExecutorTests: XCTestCase {
    func testClaudeExecutionUsesOnlyAppOwnedSafetyArguments() async throws {
        let fixture = try await makeFixture(providerID: "claude", script: Self.claudeScript)

        let output = try await fixture.executor.execute(
            configuration: fixture.configuration,
            packet: fixture.packet,
            prompt: "Review the packet",
            runID: fixture.packet.runID,
            generation: 2,
            executionID: "inspect-claude"
        )

        XCTAssertEqual(output, "CLAUDE-OK")
        let arguments = try arguments(at: fixture.argumentsURL)
        XCTAssertTrue(arguments.contains("--safe-mode"))
        XCTAssertTrue(arguments.contains("--restricted"))
        XCTAssertTrue(arguments.contains("--strict-mcp-config"))
        XCTAssertTrue(arguments.contains("--no-session-persistence"))
        XCTAssertEqual(value(after: "--permission-prompts", in: arguments), "none")
        XCTAssertEqual(value(after: "--permission-mode", in: arguments), "dontAsk")
        XCTAssertEqual(value(after: "--tools", in: arguments), "Read,Grep,Glob,LS")
        XCTAssertEqual(value(after: "--model", in: arguments), fixture.configuration.launchModel)
        XCTAssertEqual(value(after: "--effort", in: arguments), fixture.configuration.effort)
    }

    func testCodexExecutionInsertsIsolationAfterExec() async throws {
        let fixture = try await makeFixture(providerID: "codex", script: Self.codexScript)

        let output = try await fixture.executor.execute(
            configuration: fixture.configuration,
            packet: fixture.packet,
            prompt: "Review the packet",
            runID: fixture.packet.runID,
            generation: 1,
            executionID: "inspect-codex"
        )

        XCTAssertEqual(output, "CODEX-OK")
        let arguments = try arguments(at: fixture.argumentsURL)
        let execIndex = try XCTUnwrap(arguments.firstIndex(of: "exec"))
        let ignoreConfigIndex = try XCTUnwrap(arguments.firstIndex(of: "--ignore-user-config"))
        XCTAssertGreaterThan(ignoreConfigIndex, execIndex)
        XCTAssertTrue(arguments.contains("--ignore-rules"))
        XCTAssertTrue(arguments.contains("--skip-git-repo-check"))
        XCTAssertTrue(arguments.contains("--strict-config"))
        XCTAssertTrue(arguments.contains("mcp_servers={}"))
        XCTAssertEqual(values(after: "--disable", in: arguments), [
            "apps", "browser_use", "computer_use", "hooks", "image_generation", "multi_agent", "plugins",
            "standalone_web_search", "web_search_request"
        ])
        XCTAssertEqual(value(after: "--sandbox", in: arguments), "read-only")
        XCTAssertEqual(value(after: "-m", in: arguments), fixture.configuration.launchModel)
        XCTAssertTrue(arguments.contains("model_reasoning_effort=\"\(fixture.configuration.effort)\""))
    }

    func testProviderAuthenticationEnvironmentIsPreserved() async throws {
        let fixture = try await makeFixture(
            providerID: "codex",
            script: Self.codexAuthenticationScript,
            environment: ["OPENAI_API_KEY": "fake-review-worker-token"]
        )

        let output = try await fixture.executor.execute(
            configuration: fixture.configuration,
            packet: fixture.packet,
            prompt: "Review the packet",
            runID: fixture.packet.runID,
            generation: 1,
            executionID: "authenticated-codex"
        )

        XCTAssertEqual(output, "AUTH-OK")
    }

    func testFailedExecutionNeverPersistsIntermediateStdout() async throws {
        for diagnostic in ["", "Provider unavailable"] {
            let fixture = try await makeFixture(providerID: "claude", script: Self.failedClaudeScript(diagnostic: diagnostic))
            do {
                _ = try await fixture.executor.execute(
                    configuration: fixture.configuration,
                    packet: fixture.packet,
                    prompt: "Review the packet",
                    runID: fixture.packet.runID,
                    generation: 1,
                    executionID: "failed-claude"
                )
                XCTFail("Expected provider failure")
            } catch let error as PullRequestReviewWorkerError {
                XCTAssertEqual(error, .commandFailed(
                    providerID: "claude",
                    exitCode: 7,
                    message: diagnostic.isEmpty ? "No provider diagnostic was returned." : diagnostic
                ))
            }
        }
    }

    func testPreflightRejectsExecutableRemovedAfterSuccessfulCheck() async throws {
        let fixture = try await makeFixture(providerID: "claude", script: Self.claudeScript)
        try await fixture.executor.preflight(fixture.configuration)
        try FileManager.default.removeItem(atPath: fixture.configuration.executablePath)

        do {
            try await fixture.executor.preflight(fixture.configuration)
            XCTFail("Expected unavailable executable")
        } catch let error as PullRequestReviewWorkerError {
            XCTAssertEqual(error, .executableUnavailable(fixture.configuration.executablePath))
        }
    }

    func testPreflightRejectsCapabilitiesChangedAtTheSamePath() async throws {
        let fixture = try await makeFixture(providerID: "claude", script: Self.claudeScript)
        try await fixture.executor.preflight(fixture.configuration)
        let replacement = Self.claudeScript.replacingOccurrences(of: "--restricted", with: "--deprecated")
        try replacement.write(toFile: fixture.configuration.executablePath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.configuration.executablePath)

        do {
            try await fixture.executor.preflight(fixture.configuration)
            XCTFail("Expected unsupported replacement executable")
        } catch let error as PullRequestReviewWorkerError {
            XCTAssertEqual(error, .missingCapabilities(providerID: "claude", flags: ["--restricted"]))
        }
    }

    func testCancelTerminatesTrackedProviderThatIgnoresTerm() async throws {
        let fixture = try await makeFixture(providerID: "claude", script: Self.suspendedClaudeScript)
        let pidURL = fixture.directory.appendingPathComponent("worker.pid")
        let task = Task {
            try await fixture.executor.execute(
                configuration: fixture.configuration,
                packet: fixture.packet,
                prompt: "Review the packet",
                runID: fixture.packet.runID,
                generation: 3,
                executionID: "suspended-claude"
            )
        }

        try await waitForFile(at: pidURL)
        let clock = ContinuousClock()
        let start = clock.now
        await fixture.executor.cancel(runID: fixture.packet.runID)
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertLessThan(start.duration(to: clock.now), .seconds(3))
        }
        XCTAssertFalse(fixture.registry.hasLiveProcesses)
    }

    func testExecutionRejectsPacketDirectoryReplacedBySymlink() async throws {
        let fixture = try await makeFixture(providerID: "codex", script: Self.codexScript)
        let runDirectory = fixture.packet.directoryURL.deletingLastPathComponent()
        let escapedRun = fixture.directory.appendingPathComponent("escaped", isDirectory: true)
        let escapedLease = escapedRun.appendingPathComponent(fixture.packet.id, isDirectory: true)
        try FileManager.default.createDirectory(at: escapedLease, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.packet.directoryURL.path)
        try FileManager.default.removeItem(at: runDirectory)
        try FileManager.default.createSymbolicLink(at: runDirectory, withDestinationURL: escapedRun)

        do {
            _ = try await fixture.executor.execute(
                configuration: fixture.configuration,
                packet: fixture.packet,
                prompt: "Review the packet",
                runID: fixture.packet.runID,
                generation: 1,
                executionID: "escaped-packet"
            )
            XCTFail("Expected packet validation failure")
        } catch let error as ReviewPacketStoreError {
            XCTAssertEqual(error, .pathEscapedRoot)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.argumentsURL.path))
    }

    private struct Fixture {
        let executor: DefaultPullRequestReviewWorkerExecutor
        let registry: PullRequestReviewWorkerProcessRegistry
        let packet: ReviewPacketLease
        let configuration: ReviewWorkerConfiguration
        let argumentsURL: URL
        let directory: URL
    }

    private func makeFixture(
        providerID: String,
        script: String,
        environment: [String: String] = [:]
    ) async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-review-worker-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let executableURL = directory.appendingPathComponent("fake-\(providerID)")
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        let argumentsURL = directory.appendingPathComponent("arguments.txt")
        let registry = PullRequestReviewWorkerProcessRegistry()
        let executor = DefaultPullRequestReviewWorkerExecutor(
            environmentBuilder: ReviewWorkerTestEnvironmentBuilder(values: environment),
            processRegistry: registry
        )
        let packetStore = ReviewPacketStore(rootDirectory: directory.appendingPathComponent("packets"))
        let packet = try await packetStore.create(runID: "run-\(providerID)", files: [
            "changes.diff": Data("diff --git a/a b/a".utf8),
            "context.json": Data("{}".utf8)
        ])
        addTeardownBlock {
            try? await packetStore.remove(runID: packet.runID)
        }
        let configuration = ReviewWorkerConfiguration(
            id: "reviewer-\(providerID)",
            providerID: providerID,
            modelOptionID: "model-option",
            launchModel: providerID == "codex" ? "gpt-test" : "claude-test",
            effort: "medium",
            executablePath: executableURL.path
        )
        return Fixture(
            executor: executor,
            registry: registry,
            packet: packet,
            configuration: configuration,
            argumentsURL: argumentsURL,
            directory: directory
        )
    }

    private func arguments(at url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline).map(String.init)
    }

    private func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.lastIndex(of: option),
              arguments.indices.contains(arguments.index(after: index)) else {
            return nil
        }
        return arguments[arguments.index(after: index)]
    }

    private func values(after option: String, in arguments: [String]) -> [String] {
        arguments.indices.compactMap { index in
            guard arguments[index] == option,
                  arguments.indices.contains(arguments.index(after: index)) else {
                return nil
            }
            return arguments[arguments.index(after: index)]
        }
    }

    private func waitForFile(at url: URL) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !FileManager.default.fileExists(atPath: url.path) {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for \(url.path)")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static let claudeScript = #"""
    #!/usr/bin/perl
    use strict;
    use FindBin qw($Bin);
    if (grep { $_ eq '--help' } @ARGV) {
        print "--safe-mode --no-session-persistence --restricted --strict-mcp-config --permission-mode dontAsk ";
        print "--permission-prompts --tools --disable-slash-commands --no-chrome\n";
        exit 0;
    }
    my $prompt = do { local $/; <STDIN> };
    open(my $args, '>', "$Bin/arguments.txt") or die $!;
    print $args join("\n", @ARGV);
    close($args);
    print qq({"type":"result","subtype":"success","is_error":false,"result":"CLAUDE-OK"}\n);
    """#

    private static func failedClaudeScript(diagnostic: String) -> String {
        #"""
        #!/usr/bin/perl
        use strict;
        if (grep { $_ eq '--help' } @ARGV) {
            print "--safe-mode --no-session-persistence --restricted --strict-mcp-config --permission-mode dontAsk ";
            print "--permission-prompts --tools --disable-slash-commands --no-chrome\n";
            exit 0;
        }
        my $prompt = do { local $/; <STDIN> };
        print qq({"type":"assistant","message":{"content":[{"type":"thinking","thinking":"private-intermediate-marker"}]}}\n);
        print STDERR "\#(diagnostic)";
        exit 7;
        """#
    }

    private static let codexScript = #"""
    #!/usr/bin/perl
    use strict;
    use FindBin qw($Bin);
    if (grep { $_ eq '--help' } @ARGV) {
        print "--ephemeral --ignore-user-config --ignore-rules --skip-git-repo-check --strict-config --disable --sandbox\n";
        exit 0;
    }
    my $prompt = do { local $/; <STDIN> };
    open(my $args, '>', "$Bin/arguments.txt") or die $!;
    print $args join("\n", @ARGV);
    close($args);
    print qq({"type":"item.completed","item":{"type":"agent_message","text":"CODEX-OK"}}\n);
    """#

    private static let codexAuthenticationScript = #"""
    #!/usr/bin/perl
    use strict;
    if (grep { $_ eq '--help' } @ARGV) {
        print "--ephemeral --ignore-user-config --ignore-rules --skip-git-repo-check --strict-config --disable --sandbox\n";
        exit 0;
    }
    my $prompt = do { local $/; <STDIN> };
    die "missing auth" unless $ENV{'OPENAI_API_KEY'} eq 'fake-review-worker-token';
    print qq({"type":"item.completed","item":{"type":"agent_message","text":"AUTH-OK"}}\n);
    """#

    private static let suspendedClaudeScript = #"""
    #!/usr/bin/perl
    use strict;
    use FindBin qw($Bin);
    if (grep { $_ eq '--help' } @ARGV) {
        print "--safe-mode --no-session-persistence --restricted --strict-mcp-config --permission-mode dontAsk ";
        print "--permission-prompts --tools --disable-slash-commands --no-chrome\n";
        exit 0;
    }
    my $prompt = do { local $/; <STDIN> };
    open(my $pid, '>', "$Bin/worker.pid") or die $!;
    print $pid $$;
    close($pid);
    $SIG{'TERM'} = sub {};
    while (1) { select undef, undef, undef, 0.05; }
    """#
}

private struct ReviewWorkerTestEnvironmentBuilder: AgentEnvironmentBuilder {
    let values: [String: String]

    func buildEnvironment(providerEnv: [String: String]?) -> [String: String] {
        values.merging(providerEnv ?? [:]) { _, provider in provider }
    }
}
