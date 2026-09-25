import Darwin
import Foundation
import XCTest

@testable import Alveary

extension PullRequestReviewWorkerExecutorTests {
    func testClaudePreflightCapturesHelpThatIsIncompleteWhenPiped() async throws {
        for stream in ["STDOUT", "STDERR"] {
            let fixture = try await makeFixture(
                harnessID: "claude",
                script: Self.fileOnlyClaudeHelp(stream: stream)
            )

            try await fixture.executor.preflight(fixture.configuration)

            XCTAssertFalse(fixture.registry.hasLiveProcesses)
        }
    }

    func testClaudePreflightRejectsFailedOrOversizedFileCapture() async throws {
        for (stream, paddingBytes, exitCode) in [("STDOUT", 100_000, 7), ("STDOUT", 300_000, 0), ("STDERR", 300_000, 0)] {
            let fixture = try await makeFixture(
                harnessID: "claude",
                script: Self.fileOnlyClaudeHelp(stream: stream, paddingBytes: paddingBytes, exitCode: exitCode)
            )

            do {
                try await fixture.executor.preflight(fixture.configuration)
                XCTFail("Expected failed or truncated capability capture")
            } catch let error as PullRequestReviewWorkerError {
                let expected: PullRequestReviewWorkerError = exitCode == 0
                    ? .executableUnavailable(fixture.configuration.executablePath)
                    : .capabilityCheckFailed(
                        harnessID: "claude",
                        exitCode: Int32(exitCode),
                        message: DefaultPullRequestReviewWorkerExecutor.missingDiagnostic
                    )
                XCTAssertEqual(error, expected)
            }
            XCTAssertFalse(fixture.registry.hasLiveProcesses)
        }
    }

    func testClaudePreflightReportsFailedCapabilityCheckDiagnostic() async throws {
        let fixture = try await makeFixture(harnessID: "claude", script: """
        #!/bin/sh
        echo "Error: broken install" >&2
        exit 3
        """)

        do {
            try await fixture.executor.preflight(fixture.configuration)
            XCTFail("Expected failed capability check")
        } catch let error as PullRequestReviewWorkerError {
            XCTAssertEqual(error, .capabilityCheckFailed(harnessID: "claude", exitCode: 3, message: "Error: broken install"))
        }
    }

    func testCancellingClaudePreflightTerminatesTheCaptureChild() async throws {
        let fixture = try await makeFixture(harnessID: "claude", script: #"""
        #!/usr/bin/perl
        use strict;
        use FindBin qw($Bin);
        $SIG{'TERM'} = sub {};
        open(my $pid, '>', "$Bin/worker.pid.tmp") or die $!;
        print $pid $$;
        close($pid);
        rename("$Bin/worker.pid.tmp", "$Bin/worker.pid") or die $!;
        while (1) { select undef, undef, undef, 0.05; }
        """#)
        let task = Task { try await fixture.executor.preflight(fixture.configuration) }
        defer { task.cancel() }
        let pidURL = fixture.directory.appendingPathComponent("worker.pid")
        try await waitForFile(at: pidURL)
        let workerPID = try XCTUnwrap(Int32(String(contentsOf: pidURL, encoding: .utf8)))

        task.cancel()

        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertFalse(fixture.registry.hasLiveProcesses)
            XCTAssertTrue(Darwin.kill(workerPID, 0) == -1 && errno == ESRCH)
        }
    }

    private static func fileOnlyClaudeHelp(stream: String, paddingBytes: Int = 100_000, exitCode: Int = 0) -> String {
        #"""
        #!/usr/bin/perl
        use strict;
        die "Expected a help probe" unless @ARGV == 1 && $ARGV[0] eq '--help';
        print \#(stream) "Usage: claude [options]\n";
        exit 0 unless -f \#(stream);
        print \#(stream) " " x \#(paddingBytes);
        print \#(stream) "--safe-mode --no-session-persistence --restricted --strict-mcp-config --permission-mode dontAsk ";
        print \#(stream) "--permission-prompts --tools --disable-slash-commands --no-chrome\n";
        exit \#(exitCode);
        """#
    }
}
