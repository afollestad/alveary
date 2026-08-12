#if DEBUG
import Darwin
import XCTest

@testable import Alveary

/// Guards the two halves of the demo storage lock's contract: it must not delay a launch that has
/// nothing to wait for — the regression that made every Developer-menu demo relaunch pay the full
/// timeout — and it must still wait while another holder has the store open.
final class DemoStorageLockTests: XCTestCase {
    private var lockURL: URL!
    private var directoryURL: URL!
    private var contendingDescriptor: Int32?

    override func setUpWithError() throws {
        try super.setUpWithError()
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DemoStorageLockTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        lockURL = directoryURL.appendingPathComponent("AlvearyDemo.lock")
    }

    override func tearDownWithError() throws {
        if let contendingDescriptor {
            close(contendingDescriptor)
            self.contendingDescriptor = nil
        }
        try? FileManager.default.removeItem(at: directoryURL)
        try super.tearDownWithError()
    }

    func testAcquiresImmediatelyWhenNothingHoldsTheLock() {
        let started = Date()
        XCTAssertTrue(DemoStorageLock.acquire(at: lockURL, timeout: 5))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    func testWaitsOutTheTimeoutWhileAnotherHolderKeepsTheLock() throws {
        // A separate open file description, so `flock` contends exactly as a second process would.
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        try XCTSkipIf(descriptor < 0, "Could not open the test lock file")
        contendingDescriptor = descriptor
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)

        let started = Date()
        XCTAssertFalse(DemoStorageLock.acquire(at: lockURL, timeout: 0.3))
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.3)
    }

    /// The wipe deletes the demo directory whole, so a lock kept inside it would be unlinked
    /// mid-flight and the next instance would lock a fresh inode nobody holds.
    func testLockFileSitsBesideTheDemoTreeRatherThanInsideIt() throws {
        let applicationSupport = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        )
        XCTAssertEqual(
            AppStorageProfile.demoStorageLockURL.deletingLastPathComponent().standardizedFileURL.path,
            applicationSupport.standardizedFileURL.path
        )
    }
}
#endif
