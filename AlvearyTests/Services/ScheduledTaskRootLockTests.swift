import Foundation
import XCTest

@testable import Alveary

final class ScheduledTaskRootLockTests: XCTestCase {
    func testAncestorWorkspaceRootsSerialize() async throws {
        let lock = ScheduledTaskRootLock()
        let firstEntered = AsyncTestSignal()
        let releaseFirst = AsyncTestSignal()
        let secondEntered = AsyncTestSignal()

        let first = Task {
            try await lock.withWorkspaceAccess(roots: ["/tmp/root"]) {
                await firstEntered.signal()
                await releaseFirst.wait()
            }
        }
        await firstEntered.wait()
        let second = Task {
            try await lock.withWorkspaceAccess(roots: ["/tmp/root/nested"]) {
                await secondEntered.signal()
            }
        }

        await yieldRepeatedly()
        let didEnterWhileBlocked = await secondEntered.isSignaled
        XCTAssertFalse(didEnterWhileBlocked)
        await releaseFirst.signal()
        _ = try await (first.value, second.value)
        let didEventuallyEnter = await secondEntered.isSignaled
        XCTAssertTrue(didEventuallyEnter)
    }

    func testDisjointWorkspaceRootsCanRunConcurrently() async throws {
        let lock = ScheduledTaskRootLock()
        let firstEntered = AsyncTestSignal()
        let releaseFirst = AsyncTestSignal()
        let secondEntered = AsyncTestSignal()

        let first = Task {
            try await lock.withWorkspaceAccess(roots: ["/tmp/first"]) {
                await firstEntered.signal()
                await releaseFirst.wait()
            }
        }
        await firstEntered.wait()
        let second = Task {
            try await lock.withWorkspaceAccess(roots: ["/tmp/second"]) {
                await secondEntered.signal()
            }
        }

        await secondEntered.wait()
        await releaseFirst.signal()
        _ = try await (first.value, second.value)
    }

    func testSameCanonicalSourceSerializesWorktreeCreation() async throws {
        let lock = ScheduledTaskRootLock()
        let firstEntered = AsyncTestSignal()
        let releaseFirst = AsyncTestSignal()
        let secondEntered = AsyncTestSignal()

        let first = Task {
            try await lock.withWorktreeCreationAccess(sourceProjectRoot: "/tmp/source") {
                await firstEntered.signal()
                await releaseFirst.wait()
            }
        }
        await firstEntered.wait()
        let second = Task {
            try await lock.withWorktreeCreationAccess(sourceProjectRoot: "/tmp/source/../source") {
                await secondEntered.signal()
            }
        }

        await yieldRepeatedly()
        let didEnterWhileBlocked = await secondEntered.isSignaled
        XCTAssertFalse(didEnterWhileBlocked)
        await releaseFirst.signal()
        _ = try await (first.value, second.value)
        let didEventuallyEnter = await secondEntered.isSignaled
        XCTAssertTrue(didEventuallyEnter)
    }

    func testWorktreeCreationSerializesAgainstOverlappingWorkspaceAccess() async throws {
        let lock = ScheduledTaskRootLock()
        let workspaceEntered = AsyncTestSignal()
        let releaseWorkspace = AsyncTestSignal()
        let creationEntered = AsyncTestSignal()

        let workspace = Task {
            try await lock.withWorkspaceAccess(roots: ["/tmp/source/granted"]) {
                await workspaceEntered.signal()
                await releaseWorkspace.wait()
            }
        }
        await workspaceEntered.wait()
        let creation = Task {
            try await lock.withWorktreeCreationAccess(sourceProjectRoot: "/tmp/source") {
                await creationEntered.signal()
            }
        }

        await yieldRepeatedly()
        let didEnterWhileBlocked = await creationEntered.isSignaled
        XCTAssertFalse(didEnterWhileBlocked)
        await releaseWorkspace.signal()
        _ = try await (workspace.value, creation.value)
        let didEventuallyEnter = await creationEntered.isSignaled
        XCTAssertTrue(didEventuallyEnter)
    }

    func testCancelledWorkspaceWaiterDoesNotBlockFollowingWork() async throws {
        let lock = ScheduledTaskRootLock()
        let firstEntered = AsyncTestSignal()
        let releaseFirst = AsyncTestSignal()
        let cancelledEntered = AsyncTestSignal()
        let finalEntered = AsyncTestSignal()

        let first = Task {
            try await lock.withWorkspaceAccess(roots: ["/tmp/root"]) {
                await firstEntered.signal()
                await releaseFirst.wait()
            }
        }
        await firstEntered.wait()
        let cancelled = Task {
            try await lock.withWorkspaceAccess(roots: ["/tmp/root"]) {
                await cancelledEntered.signal()
            }
        }
        await yieldRepeatedly()
        cancelled.cancel()

        let final = Task {
            try await lock.withWorkspaceAccess(roots: ["/tmp/root"]) {
                await finalEntered.signal()
            }
        }
        await releaseFirst.signal()
        _ = try await first.value
        do {
            _ = try await cancelled.value
            XCTFail("Expected the queued access to be cancelled")
        } catch is CancellationError {
            // Expected.
        }
        _ = try await final.value
        let didCancelledOperationEnter = await cancelledEntered.isSignaled
        let didFinalOperationEnter = await finalEntered.isSignaled
        XCTAssertFalse(didCancelledOperationEnter)
        XCTAssertTrue(didFinalOperationEnter)
    }

    func testInvalidOrMissingRootsCannotRunUnlocked() async {
        let lock = ScheduledTaskRootLock()

        do {
            try await lock.withWorkspaceAccess(roots: ["relative"]) {}
            XCTFail("Expected a relative workspace root to be rejected")
        } catch {
            XCTAssertEqual(error as? ScheduledTaskRootLockError, .invalidRoot("relative"))
        }

        do {
            try await lock.withWorkspaceAccess(roots: []) {}
            XCTFail("Expected an empty workspace root set to be rejected")
        } catch {
            XCTAssertEqual(error as? ScheduledTaskRootLockError, .missingWorkspaceRoots)
        }

        do {
            try await lock.withWorktreeCreationAccess(sourceProjectRoot: "relative") {}
            XCTFail("Expected a relative worktree source to be rejected")
        } catch {
            XCTAssertEqual(error as? ScheduledTaskRootLockError, .invalidRoot("relative"))
        }
    }

    func testCancellationAfterGrantDoesNotPoisonFutureRequests() async throws {
        let lock = ScheduledTaskRootLock()
        let entered = AsyncTestSignal()
        let release = AsyncTestSignal()
        let first = Task {
            try await lock.withWorkspaceAccess(roots: ["/tmp/root"]) {
                await entered.signal()
                await release.wait()
            }
        }
        await entered.wait()

        first.cancel()
        await release.signal()
        _ = try await first.value

        let enteredAgain = AsyncTestSignal()
        try await lock.withWorkspaceAccess(roots: ["/tmp/root"]) {
            await enteredAgain.signal()
        }
        let didEnterAgain = await enteredAgain.isSignaled
        XCTAssertTrue(didEnterAgain)
    }
}

private actor AsyncTestSignal {
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var isSignaled: Bool { signaled }

    func signal() {
        guard !signaled else {
            return
        }
        signaled = true
        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume() }
    }

    func wait() async {
        guard !signaled else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private func yieldRepeatedly() async {
    for _ in 0 ..< 20 {
        await Task.yield()
    }
}
