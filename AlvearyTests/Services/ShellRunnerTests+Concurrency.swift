import Foundation
import XCTest

@testable import Alveary

extension ShellRunnerTests {
    func testBusyReviewWorkersDoNotBlockAnotherCommandsInputAndOutput() async throws {
        let workerCount = max(18, ProcessInfo.processInfo.activeProcessorCount + 2)
        let workersLaunched = expectation(description: "All quiet workers launched")
        workersLaunched.expectedFulfillmentCount = workerCount
        let tracker = ShellConcurrencyLaunchTracker(launched: workersLaunched)
        let workerRunner = DefaultShellRunner(processTracker: tracker)
        let input = String(repeating: "A", count: 200_000)

        try await withThrowingTaskGroup(of: Void.self) { group in
            defer { group.cancelAll() }
            for _ in 0..<workerCount {
                group.addTask {
                    // The alarm bounds a broken runner; successful tests cancel workers as soon as the command completes.
                    _ = try? await workerRunner.run(
                        executable: "/usr/bin/perl",
                        args: ["-e", "use POSIX qw(pause); $SIG{ALRM}=sub { exit 0 }; alarm 8; pause();"],
                        processGroupPolicy: .create, timeout: .seconds(10),
                        stdoutLimitBytes: 4_096, stderrLimitBytes: 4_096, standardInput: .nullDevice
                    )
                }
            }
            await fulfillment(of: [workersLaunched], timeout: 5)
            XCTAssertEqual(tracker.activeCount, workerCount)

            let result = try await DefaultShellRunner().run(
                executable: "/usr/bin/perl",
                args: ["-e", "local $/; my $input=<STDIN>; print $input; print STDERR 'B' x length($input);"],
                timeout: .seconds(2), stdoutLimitBytes: 4_096, stderrLimitBytes: 4_096,
                standardInput: .text(input)
            )

            XCTAssertTrue(result.succeeded)
            XCTAssertEqual(result.stdout, String(repeating: "A", count: 4_096))
            XCTAssertEqual(result.stderr, String(repeating: "B", count: 4_096))
            XCTAssertTrue(result.stdoutWasTruncated)
            XCTAssertTrue(result.stderrWasTruncated)
            XCTAssertEqual(tracker.activeCount, workerCount)
        }
    }
}

private final class ShellConcurrencyLaunchTracker: ShellProcessTracking, @unchecked Sendable {
    init(launched: XCTestExpectation) {
        self.launched = launched
    }

    var activeCount: Int { count.withLock { $0 } }

    func register(_ process: Process, processGroupID: Int32?) -> Bool {
        count.withLock { $0 += 1 }
        launched.fulfill()
        return true
    }

    func unregister(_ process: Process) {
        count.withLock { $0 -= 1 }
    }

    private let launched: XCTestExpectation
    private let count = LockedState(0)
}
