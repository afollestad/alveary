import Darwin
import Foundation
import XCTest

@testable import Alveary

extension ShellRunnerTests {
    func testExpiredDrainDeadlineStillObservesEOF() throws {
        let pipe = Pipe()
        defer { try? pipe.fileHandleForReading.close() }
        try pipe.fileHandleForWriting.close()
        let stopController = ShellIOStopController(drainTimeout: 0)
        stopController.beginDeadline()

        let capture = DefaultShellRunner.readNonBlocking(
            from: pipe.fileHandleForReading.fileDescriptor, maxBytes: nil, stopController: stopController
        )

        XCTAssertNil(capture.failure)
        XCTAssertTrue(capture.data.isEmpty)
    }

    func testExpiredDrainDeadlineCapturesOneFinalReadWithoutWaitingForWriter() throws {
        let pipe = Pipe()
        defer {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }
        try pipe.fileHandleForWriting.write(contentsOf: Data("queued".utf8))
        let stopController = ShellIOStopController(drainTimeout: 0)
        stopController.beginDeadline()

        let capture = DefaultShellRunner.readNonBlocking(
            from: pipe.fileHandleForReading.fileDescriptor, maxBytes: 3, stopController: stopController
        )

        XCTAssertEqual(capture.failure, .drainTimedOut)
        XCTAssertEqual(capture.data, Data("que".utf8))
        XCTAssertTrue(capture.wasTruncated)
    }

    func testOutputDescriptorFailuresAreNotReportedAsDrainTimeouts() {
        let pipe = Pipe()
        defer {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }
        for descriptor in [-1, pipe.fileHandleForWriting.fileDescriptor] {
            let capture = DefaultShellRunner.readNonBlocking(
                from: descriptor, maxBytes: nil, stopController: ShellIOStopController()
            )
            XCTAssertEqual(capture.failure, .readFailed(EBADF))
        }
    }

    func testEscapedDescendantRetainingStdoutReportsBoundedCaptureAndExitStatus() async throws {
        let registry = PullRequestReviewWorkerProcessRegistry()
        let tracker = registry.tracker(for: .init(runID: "run", generation: 1, executionID: "escaped-pipes"))
        let runner = DefaultShellRunner(processTracker: tracker)
        let start = ContinuousClock.now
        do {
            _ = try await runner.run(
                executable: "/usr/bin/perl", args: ["-e", Self.escapedOutputChildScript],
                processGroupPolicy: .create, timeout: .seconds(8), stdoutLimitBytes: 4_096,
                stderrLimitBytes: 4_096, standardInput: .nullDevice
            )
            XCTFail("Expected the detached child's inherited output pipe to remain open")
        } catch let ShellError.ioFailure(failure) {
            XCTAssertTrue(failure.exitedNormally)
            XCTAssertTrue(failure.result.succeeded)
            XCTAssertTrue(failure.inputCompleted)
            XCTAssertEqual(failure.stdoutFailure, .drainTimedOut)
            XCTAssertNil(failure.stderrFailure)
            XCTAssertEqual(failure.result.stdoutData, Data([0xFF, 0x41]))
            XCTAssertEqual(failure.result.stderr, "provider diagnostic\n")
            XCTAssertFalse(failure.result.stdoutWasTruncated)
            XCTAssertFalse(registry.hasLiveProcesses)
            XCTAssertLessThan(start.duration(to: .now), .seconds(5))
        }
    }

    func testEarlyStdinClosureRetainsNonzeroExitAndStderr() async throws {
        do {
            _ = try await DefaultShellRunner().run(
                executable: "/usr/bin/perl",
                args: ["-e", "close STDIN; print STDERR qq(invalid model\\n); exit 7;"],
                processGroupPolicy: .create, timeout: .seconds(5),
                standardInput: .text(String(repeating: "x", count: 4 * 1024 * 1024))
            )
            XCTFail("Expected incomplete standard input")
        } catch let ShellError.ioFailure(failure) {
            XCTAssertTrue(failure.exitedNormally)
            XCTAssertEqual(failure.result.exitCode, 7)
            XCTAssertEqual(failure.result.stderr, "invalid model\n")
            XCTAssertFalse(failure.inputCompleted)
            XCTAssertNil(failure.stdoutFailure)
            XCTAssertNil(failure.stderrFailure)
            XCTAssertTrue(failure.description.contains("exited with code 7"))
            XCTAssertTrue(failure.description.contains("invalid model"))
        }
    }

    func testIODiagnosticsNameFailuresAndBoundStderrWithoutExposingStdout() {
        let failure = ShellIOFailure(
            executable: "codex", result: ShellResult(
                stdout: "private-stdout-marker", stderr: String(repeating: "雪", count: 1_000), exitCode: 7,
                stdoutWasTruncated: false, stderrWasTruncated: true
            ), exitedNormally: true, inputCompleted: false,
            stdoutFailure: .readFailed(EBADF), stderrFailure: .drainTimedOut
        )
        let error = ShellError.ioFailure(failure)
        for diagnostic in [error.localizedDescription, String(describing: error), String(reflecting: error),
                           String(describing: failure), String(reflecting: failure)] {
            XCTAssertTrue(diagnostic.contains("exited with code 7"))
            XCTAssertTrue(diagnostic.contains("standard input was not fully delivered"))
            XCTAssertTrue(diagnostic.contains("stdout could not be read (errno \(EBADF))"))
            XCTAssertTrue(diagnostic.contains("stderr did not close before the I/O deadline"))
            XCTAssertTrue(diagnostic.contains("雪"))
            XCTAssertFalse(diagnostic.contains("private-stdout-marker"))
            XCTAssertFalse(diagnostic.contains("�"))
            XCTAssertLessThan(diagnostic.utf8.count, 2_300)
        }
        let signalled = ShellIOFailure(
            executable: "codex", result: failure.result, exitedNormally: false, inputCompleted: true,
            stdoutFailure: .drainTimedOut, stderrFailure: nil
        )
        XCTAssertTrue(ShellError.ioFailure(signalled).localizedDescription.contains("was terminated by signal 7"))
    }

    /// Synchronize detachment before the leader exits; the escaped child has a fixed lifetime even on test failure.
    private static let escapedOutputChildScript = #"""
    use POSIX qw(setsid);
    $|=1;
    pipe(my $reader, my $writer) or die "pipe failed";
    my $child=fork();
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
    my $ready=<$reader>;
    close $reader;
    print pack('C*', 0xff, 0x41);
    print STDERR "provider diagnostic\n";
    exit 0;
    """#
}
