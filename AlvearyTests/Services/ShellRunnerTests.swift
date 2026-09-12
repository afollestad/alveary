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

    func testAdditionalPathDirectoriesAreVisibleToChildProcesses() async throws {
        let toolsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: toolsDirectory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: toolsDirectory) }

        let executableURL = toolsDirectory.appendingPathComponent("alveary-test-tool")
        try """
        #!/bin/sh
        printf 'found'
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let runner = DefaultShellRunner(additionalPathDirectories: [toolsDirectory.path])
        let result = try await runner.run(
            executable: "/bin/sh",
            args: ["-c", "alveary-test-tool"]
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.stdout, "found")
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

    func testTextStandardInputWritesTextAndClosesThePipe() async throws {
        let runner = DefaultShellRunner()

        let result = try await runner.run(
            executable: "/bin/cat",
            args: [],
            standardInput: .text("review packet prompt")
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.stdout, "review packet prompt")
    }

    func testReplacementEnvironmentDoesNotInheritParentValues() async throws {
        let runner = DefaultShellRunner()

        let result = try await runner.run(
            executable: "/usr/bin/env",
            args: [],
            environment: ["REVIEW_WORKER_TEST": "present"],
            environmentPolicy: .replace,
            standardInput: .nullDevice
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.stdout.contains("REVIEW_WORKER_TEST=present"))
        XCTAssertFalse(result.stdout.contains("HOME="))
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

    func testProcessGroupKillsTermIgnoringChildThatRetainsOutputAfterParentExit() async throws {
        let runner = DefaultShellRunner()
        let clock = ContinuousClock()
        let start = clock.now

        let result = try await runner.run(
            executable: "/usr/bin/perl",
            args: ["-e", Self.termIgnoringChildScript(parentExits: true)],
            processGroupPolicy: .create,
            timeout: .seconds(5)
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.stdout.contains("parent\n"))
        XCTAssertTrue(result.stdout.contains("child\n"))
        XCTAssertLessThan(start.duration(to: clock.now), .seconds(4))
    }

    func testProcessGroupKeepsClosedPipeDescendantRegisteredThroughForceKill() async throws {
        let registry = PullRequestReviewWorkerProcessRegistry()
        let tracker = registry.tracker(for: .init(runID: "run", generation: 1, executionID: "closed-pipes"))
        let runner = DefaultShellRunner(processTracker: tracker)
        let clock = ContinuousClock()
        let start = clock.now

        let result = try await runner.run(
            executable: "/usr/bin/perl",
            args: ["-e", Self.closedPipeChildScript],
            processGroupPolicy: .create,
            timeout: .seconds(5)
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.stdout, "parent\n")
        XCTAssertGreaterThan(start.duration(to: clock.now), .seconds(1))
        XCTAssertLessThan(start.duration(to: clock.now), .seconds(4))
        XCTAssertFalse(registry.hasLiveProcesses)
    }

    func testProcessGroupTimeoutKillsTermIgnoringDescendants() async throws {
        let runner = DefaultShellRunner()
        let clock = ContinuousClock()
        let start = clock.now

        do {
            _ = try await runner.run(
                executable: "/usr/bin/perl",
                args: ["-e", Self.termIgnoringChildScript(parentExits: false)],
                processGroupPolicy: .create,
                timeout: .milliseconds(100)
            )
            XCTFail("Expected timeout")
        } catch let ShellError.timeout(executable, timeout) {
            XCTAssertEqual(executable, "/usr/bin/perl")
            XCTAssertEqual(timeout, .milliseconds(100))
            XCTAssertLessThan(start.duration(to: clock.now), .seconds(4))
        }
    }

    func testProcessGroupFailsClosedWhenChildClosesStandardInputEarly() async throws {
        let runner = DefaultShellRunner()
        let clock = ContinuousClock()
        let start = clock.now

        do {
            _ = try await runner.run(
                executable: "/usr/bin/perl",
                args: ["-e", "close STDIN; print qq(done\\n); select undef, undef, undef, 0.1;"],
                processGroupPolicy: .create,
                timeout: .seconds(5),
                standardInput: .text(String(repeating: "x", count: 4 * 1024 * 1024))
            )
            XCTFail("Expected incomplete standard input")
        } catch let ShellError.ioDrainTimedOut(executable) {
            XCTAssertEqual(executable, "/usr/bin/perl")
            XCTAssertLessThan(start.duration(to: clock.now), .seconds(4))
        }
    }

    func testProcessGroupCancellationKillsTermIgnoringDescendants() async throws {
        let registry = PullRequestReviewWorkerProcessRegistry()
        let script = Self.termIgnoringChildScript(parentExits: false)
        let task = Task.detached { [registry] in
            let tracker = registry.tracker(for: .init(runID: "run", generation: 1, executionID: "cancel"))
            let runner = DefaultShellRunner(processTracker: tracker)
            return try await runner.run(
                executable: "/usr/bin/perl",
                args: ["-e", script],
                processGroupPolicy: .create
            )
        }
        try await waitForLiveProcess(in: registry)

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertFalse(registry.hasLiveProcesses)
        }
    }

    func testProcessGroupShutdownKillsTermIgnoringDescendants() async throws {
        let registry = PullRequestReviewWorkerProcessRegistry()
        let script = Self.termIgnoringChildScript(parentExits: false)
        let task = Task.detached { [registry] in
            let tracker = registry.tracker(for: .init(runID: "run", generation: 1, executionID: "shutdown"))
            let runner = DefaultShellRunner(processTracker: tracker)
            return try await runner.run(
                executable: "/usr/bin/perl",
                args: ["-e", script],
                processGroupPolicy: .create
            )
        }
        try await waitForLiveProcess(in: registry)

        registry.terminateAllSynchronously(grace: 0.05)
        XCTAssertFalse(registry.hasLiveProcesses)
        let result = try await task.value

        XCTAssertFalse(result.succeeded)
    }

    func testProcessGroupShutdownFindsDescendantAfterParentAndPipesExit() async throws {
        let registry = PullRequestReviewWorkerProcessRegistry()
        let script = Self.closedPipeChildScript
        let task = Task.detached { [registry] in
            let tracker = registry.tracker(for: .init(runID: "run", generation: 1, executionID: "orphan-shutdown"))
            let runner = DefaultShellRunner(processTracker: tracker)
            return try await runner.run(
                executable: "/usr/bin/perl",
                args: ["-e", script],
                processGroupPolicy: .create
            )
        }
        try await waitForTrackedLeaderExit(in: registry)
        XCTAssertTrue(registry.hasLiveProcesses)

        let clock = ContinuousClock()
        let start = clock.now
        registry.terminateAllSynchronously(grace: 0.05)
        XCTAssertFalse(registry.hasLiveProcesses)
        let result = try await task.value

        XCTAssertTrue(result.succeeded)
        XCTAssertLessThan(start.duration(to: clock.now), .seconds(1))
    }

    private func waitForLiveProcess(in registry: PullRequestReviewWorkerProcessRegistry) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !registry.hasLiveProcesses {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for the process to launch")
                return
            }
            await Task.yield()
        }
    }

    private func waitForTrackedLeaderExit(in registry: PullRequestReviewWorkerProcessRegistry) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while registry.allProcessesSnapshot.first?.isRunning != false {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for the parent process to exit")
                return
            }
            await Task.yield()
        }
    }

    private static func termIgnoringChildScript(parentExits: Bool) -> String {
        """
        $SIG{TERM}=sub{};
        $|=1;
        print "parent\\n";
        my $child=fork();
        die "fork failed" unless defined $child;
        if ($child == 0) {
            print "child\\n";
            while (1) { select undef, undef, undef, 0.01; }
        }
        \(parentExits ? "exit 0;" : "while (1) { select undef, undef, undef, 0.01; }")
        """
    }

    private static let closedPipeChildScript = """
    $SIG{TERM}=sub{};
    $|=1;
    print "parent\\n";
    my $child=fork();
    die "fork failed" unless defined $child;
    if ($child == 0) {
        close STDOUT;
        close STDERR;
        while (1) { select undef, undef, undef, 0.01; }
    }
    exit 0;
    """
}
