import Foundation
import XCTest

@testable import Alveary

final class ShellRunnerTests: XCTestCase {
    func testShellRunOptionsDefaultsToInheritedStandardInput() {
        XCTAssertEqual(ShellRunOptions().standardInput, .inherit)
    }

    func testEnvironmentOverlayMergesIntoInheritedEnvironment() async throws {
        let runner = DefaultShellRunner()

        let result = try await runner.run(
            executable: "/bin/sh",
            args: ["-c", "printf '%s:%s' \"$SKEP_TEST_ONLY\" \"${PATH:+present}\""],
            environment: ["SKEP_TEST_ONLY": "value"]
        )

        XCTAssertEqual(result.stdout, "value:present")
        XCTAssertTrue(result.succeeded)
    }

    func testNullStandardInputPresentsEOFToChildProcess() async throws {
        let runner = DefaultShellRunner()

        let result = try await runner.run(
            executable: "/usr/bin/perl",
            args: ["-e", "my $line = <STDIN>; print defined($line) ? 'input' : 'eof';"],
            standardInput: .nullDevice
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.stdout, "eof")
    }

    func testNonZeroExitCapturesStderrAndExitCode() async throws {
        let runner = DefaultShellRunner()

        let result = try await runner.run(
            executable: "/bin/sh",
            args: ["-c", "printf 'oops' >&2; exit 7"]
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertEqual(result.stderr, "oops")
    }

    func testBoundedOutputCapturesAndTruncatesBothStreamsWithoutDeadlocking() async throws {
        let runner = DefaultShellRunner()

        let result = try await runner.run(
            executable: "/usr/bin/perl",
            args: ["-e", "print 'A' x 50000; print STDERR 'B' x 50000;"],
            stdoutLimitBytes: 1024,
            stderrLimitBytes: 2048
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.stdout.count, 1024)
        XCTAssertEqual(result.stderr.count, 2048)
        XCTAssertTrue(result.stdoutWasTruncated)
        XCTAssertTrue(result.stderrWasTruncated)
    }

    func testStdoutDataPreservesNonUTF8Bytes() async throws {
        let runner = DefaultShellRunner()

        let result = try await runner.run(
            executable: "/usr/bin/perl",
            args: ["-e", "print pack('C*', 0x89, 0x50, 0x4e, 0x47, 0x00, 0xff);"]
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.stdoutData, Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF]))
    }

    func testBoundedOutputDrainsStdoutBeyondPipeCapacity() async throws {
        let runner = DefaultShellRunner()

        let result = try await runner.run(
            executable: "/usr/bin/perl",
            args: ["-e", "print 'A' x 200000;"],
            timeout: .seconds(5),
            stdoutLimitBytes: 4096
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.stdout.count, 4096)
        XCTAssertTrue(result.stdoutWasTruncated)
    }

    func testTimeoutTerminatesLongRunningProcess() async throws {
        let runner = DefaultShellRunner()
        let clock = ContinuousClock()
        let start = clock.now

        do {
            _ = try await runner.run(
                executable: "/usr/bin/perl",
                args: ["-e", "$SIG{TERM}=sub{}; sleep 10;"],
                timeout: .milliseconds(100)
            )
            XCTFail("Expected timeout")
        } catch let ShellError.timeout(executable, timeout) {
            XCTAssertEqual(executable, "/usr/bin/perl")
            XCTAssertEqual(timeout, .milliseconds(100))
            XCTAssertLessThan(start.duration(to: clock.now), .seconds(3))
        }
    }

    func testCancellationTerminatesChildProcess() async throws {
        let runner = DefaultShellRunner()
        let clock = ContinuousClock()
        let start = clock.now

        let task = Task {
            try await runner.run(
                executable: "/bin/sh",
                args: ["-c", "sleep 10"]
            )
        }

        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertLessThan(start.duration(to: clock.now), .seconds(3))
        }
    }

    func testCancellationWhileStreamingOutputDoesNotCrash() async throws {
        let runner = DefaultShellRunner()
        let clock = ContinuousClock()
        let start = clock.now
        let script = #"""
        $SIG{TERM}=sub{};
        $|=1;
        select STDERR;
        $|=1;
        select STDOUT;
        while (1) {
            print 'A' x 1024;
            print STDERR 'B' x 1024;
            select undef, undef, undef, 0.01;
        }
        """#

        let task = Task {
            try await runner.run(
                executable: "/usr/bin/perl",
                args: ["-e", script],
                stdoutLimitBytes: 4096,
                stderrLimitBytes: 4096
            )
        }

        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertLessThan(start.duration(to: clock.now), .seconds(3))
        }
    }
}
