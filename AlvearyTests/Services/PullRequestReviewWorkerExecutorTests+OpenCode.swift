import Foundation
import XCTest

@testable import Alveary

extension PullRequestReviewWorkerExecutorTests {
    func testOpenCodeReviewPreflightAndExecutionUseDisposableProfile() async throws {
        let execution = OpenCodeReviewExecutionShellRunner()
        let fixture = try await makeFixture(
            harnessID: "opencode", script: Self.openCodeScript(outcome: "success"), executionShellRunner: execution
        )
        try await fixture.executor.preflight(fixture.configuration)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.argumentsURL.path))

        let output = try await fixture.executor.execute(
            configuration: fixture.configuration, packet: fixture.packet, prompt: "Review the packet", runID: fixture.packet.runID,
            generation: 1, executionID: "opencode"
        )

        XCTAssertEqual(output, "OPENCODE-OK")
        let recordedOptions = await execution.lastOptions
        let options = try XCTUnwrap(recordedOptions)
        XCTAssertEqual(options.environmentPolicy, .replace)
        XCTAssertEqual(options.processGroupPolicy, .create)
        XCTAssertLessThan(try XCTUnwrap(options.timeout), .seconds(20 * 60))
        let arguments = try String(contentsOf: fixture.argumentsURL, encoding: .utf8).components(separatedBy: .newlines)
        XCTAssertEqual(arguments.prefix(5), ["run", "--format", "json", "--model", "provider/model"])
        XCTAssertFalse(arguments.contains("--variant"))
        XCTAssertEqual(try String(contentsOf: fixture.directory.appendingPathComponent("prompt.txt"), encoding: .utf8), "Review the packet")
        try assertOpenCodeProfilesRemoved(fixture)
        XCTAssertFalse(fixture.registry.hasLiveProcesses)
    }

    func testOpenCodeReviewFailureAndCancellationCleanDisposableProfile() async throws {
        for outcome in ["failure", "cancel"] {
            let fixture = try await makeFixture(harnessID: "opencode", script: Self.openCodeScript(outcome: outcome))
            let task = Task {
                try await fixture.executor.execute(
                    configuration: fixture.configuration, packet: fixture.packet, prompt: "Review", runID: fixture.packet.runID,
                    generation: 1, executionID: outcome
                )
            }
            if outcome == "cancel" {
                try await waitForFile(at: fixture.argumentsURL)
                await fixture.executor.cancel(runID: fixture.packet.runID)
            }
            do {
                _ = try await task.value
                XCTFail("Expected \(outcome)")
            } catch is CancellationError {
                XCTAssertEqual(outcome, "cancel")
            } catch let error as PullRequestReviewWorkerError {
                XCTAssertEqual(error, .commandFailed(harnessID: "opencode", exitCode: 7, message: "Native failed"))
            }
            try assertOpenCodeProfilesRemoved(fixture)
            XCTAssertFalse(fixture.registry.hasLiveProcesses)
        }
    }

    func testOpenCodeReviewRejectsPacketReplacementDuringPreparation() async throws {
        let fixture = try await makeFixture(harnessID: "opencode", script: Self.openCodeScript(outcome: "replace"))
        let task = Task {
            try await fixture.executor.execute(
                configuration: fixture.configuration, packet: fixture.packet, prompt: "Review", runID: fixture.packet.runID,
                generation: 1, executionID: "replace"
            )
        }
        try await waitForFile(at: fixture.directory.appendingPathComponent("probe.waiting"))
        let escaped = fixture.directory.appendingPathComponent("escaped", isDirectory: true)
        try FileManager.default.createDirectory(at: escaped, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.packet.directoryURL.path)
        try FileManager.default.removeItem(at: fixture.packet.directoryURL)
        try FileManager.default.createSymbolicLink(at: fixture.packet.directoryURL, withDestinationURL: escaped)
        try Data().write(to: fixture.directory.appendingPathComponent("probe.release"))
        do {
            _ = try await task.value
            XCTFail("Expected packet validation failure")
        } catch let error as ReviewPacketStoreError {
            XCTAssertEqual(error, .pathEscapedRoot)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.argumentsURL.path))
        try assertOpenCodeProfilesRemoved(fixture)
        XCTAssertFalse(fixture.registry.hasLiveProcesses)
    }

    private func assertOpenCodeProfilesRemoved(_ fixture: Fixture) throws {
        let paths = try String(contentsOf: fixture.directory.appendingPathComponent("profiles.txt"), encoding: .utf8)
            .split(whereSeparator: \.isNewline)
        XCTAssertFalse(paths.isEmpty)
        for path in paths { XCTAssertFalse(FileManager.default.fileExists(atPath: String(path))) }
    }

    private static func openCodeScript(outcome: String) -> String {
        #"""
        #!/usr/bin/perl
        use strict;
        use FindBin qw($Bin);
        use JSON::PP;
        open(my $profiles, '>>', "$Bin/profiles.txt") or die $!;
        print $profiles "$ENV{HOME}\n";
        close($profiles);
        die "inherited home" if $ENV{HOME} eq $Bin;
        die "project config enabled" unless $ENV{OPENCODE_DISABLE_PROJECT_CONFIG} eq 'true';
        if ($ARGV[0] eq '--version') { print "1.18.32\n"; exit; }
        if ($ARGV[0] eq 'models') {
            if ('\#(outcome)' eq 'replace') {
                open(my $waiting, '>', "$Bin/probe.waiting") or die $!; close($waiting);
                while (!-e "$Bin/probe.release") { select undef, undef, undef, 0.01; }
            }
            print qq(provider/model\n{\n  "variants": {}\n}\n); exit;
        }
        open(my $config_file, '<', $ENV{OPENCODE_CONFIG}) or die $!;
        my $config = decode_json(do { local $/; <$config_file> });
        die "unsafe tools" unless $config->{permission}{'*'} eq 'deny' && $config->{permission}{read} eq 'allow';
        my $prompt = do { local $/; <STDIN> };
        open(my $prompt_file, '>', "$Bin/prompt.txt") or die $!;
        print $prompt_file $prompt;
        close($prompt_file);
        open(my $args, '>', "$Bin/arguments.txt") or die $!;
        print $args join("\n", @ARGV);
        close($args);
        if ('\#(outcome)' eq 'failure') { print STDERR 'Native failed'; exit 7; }
        if ('\#(outcome)' eq 'cancel') { $SIG{'TERM'} = sub {}; while (1) { select undef, undef, undef, 0.05; } }
        print qq({"type":"text","sessionID":"session","part":{"id":"text","messageID":"message","text":"OPENCODE-OK","time":{"end":1}}}\n);
        print qq({"type":"step_finish","sessionID":"session","part":{"messageID":"message","reason":"stop"}}\n);
        """#
    }
}

private actor OpenCodeReviewExecutionShellRunner: ShellRunner {
    private(set) var lastOptions: ShellRunOptions?

    func run(executable: String, args: [String], in directory: String?, options: ShellRunOptions) async throws -> ShellResult {
        lastOptions = options
        return try await DefaultShellRunner().run(executable: executable, args: args, in: directory, options: options)
    }
}
