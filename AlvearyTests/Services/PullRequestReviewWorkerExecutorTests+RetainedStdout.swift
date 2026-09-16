import Foundation
import XCTest

@testable import Alveary

extension PullRequestReviewWorkerExecutorTests {
    func testCompletedCodexTurnRecoversFromRealDescendantRetainingStdout() async throws {
        let fixture = try await makeFixture(harnessID: "codex", script: retainedStdoutScript(duringHelp: false))
        let start = ContinuousClock.now

        let output = try await executeIOFixture(fixture)

        XCTAssertEqual(output, "{\"findings\":[]}")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.argumentsURL.path))
        XCTAssertFalse(fixture.registry.hasLiveProcesses)
        // Return before the child's six-second lifetime ends, proving recovery did not wait for natural EOF.
        XCTAssertLessThan(start.duration(to: .now), .seconds(5))
    }

    func testRealDescendantRetainingHelpStdoutReportsCapabilityFailureWithoutExecuting() async throws {
        let fixture = try await makeFixture(harnessID: "codex", script: retainedStdoutScript(duringHelp: true))
        let start = ContinuousClock.now

        do {
            _ = try await executeIOFixture(fixture)
            XCTFail("Expected capability check to reject its retained stdout")
        } catch let error as ReviewWorkerIOFailure {
            XCTAssertEqual(error.stage, .capabilityCheck)
            XCTAssertNil(error.codexCompletion)
            XCTAssertTrue(error.failure.exitedNormally)
            XCTAssertEqual(error.failure.result.exitCode, 0)
            XCTAssertEqual(error.failure.stdoutFailure, .drainTimedOut)
            XCTAssertNil(error.failure.stderrFailure)
            XCTAssertTrue(error.localizedDescription.contains("Capability check failed"))
            XCTAssertTrue(error.localizedDescription.contains("stdout did not close before the I/O deadline"))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.argumentsURL.path))
        XCTAssertFalse(fixture.registry.hasLiveProcesses)
        XCTAssertLessThan(start.duration(to: .now), .seconds(5))
    }

    /// The handshake guarantees the child escapes group teardown before its parent exits; its lifetime stays bounded on failure.
    private func retainedStdoutScript(duringHelp: Bool) throws -> String {
        let stream = try ReviewWorkerIOTestSupport.codexStream(finalText: "{\"findings\":[]}")
        return #"""
        #!/usr/bin/perl
        use strict;
        use POSIX qw(setsid);
        use FindBin qw($Bin);
        $|=1;
        if (grep { $_ eq '--help' } @ARGV) {
            print <<'CAPABILITIES';
        \#(ReviewWorkerIOTestSupport.help)
        CAPABILITIES
            exit 0 unless \#(duringHelp ? 1 : 0);
        } else {
            my $prompt = do { local $/; <STDIN> };
            open(my $args, '>', "$Bin/arguments.txt") or die $!;
            print $args join("\n", @ARGV);
            close $args;
            print <<'EVENTS';
        \#(stream)
        EVENTS
        }
        pipe(my $reader, my $writer) or die "pipe failed";
        my $child = fork();
        die "fork failed" unless defined $child;
        if ($child == 0) {
            close $reader;
            setsid() >= 0 or die "setsid failed";
            close STDIN;
            close STDERR;
            print $writer "ready\n";
            close $writer;
            select undef, undef, undef, 6;
            exit 0;
        }
        close $writer;
        my $ready = <$reader>;
        close $reader;
        exit 0;
        """#
    }
}
