#if DEBUG
import Darwin
import Foundation

/// Keeps a starting demo instance from wiping storage out from under the instance it replaces.
///
/// A demo instance holds this lock for its whole lifetime, so it is held exactly while the demo
/// store may be open. The kernel drops it when the process exits, which means a crashed or killed
/// instance cannot strand it.
///
/// **Never wait on the predecessor's process exit instead.** `DemoMode.relaunch` terminates only
/// once LaunchServices reports the successor launched, and that report comes *after*
/// `AlvearyApp.init`, where this runs. Waiting for the old process to disappear is therefore a
/// mutual wait that both sides lose: it costs every demo relaunch the full timeout, then wipes
/// anyway because the wait is bounded. Waiting on the lock instead clears as soon as the store is
/// released, and a predecessor that never opened the demo store — the production-to-demo relaunch
/// the Developer menu performs — never blocks the successor at all.
enum DemoStorageLock {
    private static let defaultTimeout: TimeInterval = 6
    private static let pollInterval: TimeInterval = 0.05

    /// Blocks — bounded — until this process holds the demo storage lock, and answers whether it
    /// got it. Called from `AppStorageProfile.demo()` immediately before the wipe, which is before
    /// the model container exists, so nothing here waits on our own storage.
    ///
    /// A timeout is deliberately not fatal: it means a predecessor is wedged holding the store
    /// open, and refusing to launch at all would be worse than the reseed that follows.
    @discardableResult
    static func acquire(at url: URL, timeout: TimeInterval = defaultTimeout) -> Bool {
        let descriptor = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else {
            return false
        }
        let deadline = Date().addingTimeInterval(timeout)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard Date() < deadline else {
                close(descriptor)
                return false
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        // Held descriptor deliberately never closed: the lock's lifetime *is* the process's
        // lifetime, and that is precisely the window a successor has to wait out.
        return true
    }
}
#endif
