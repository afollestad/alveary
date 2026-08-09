#if DEBUG
import AppKit
import Foundation

/// Keeps a relaunching demo instance from wiping storage out from under the instance it replaces.
///
/// `NSApp.terminate` only starts the shutdown: `applicationWillTerminate` can block for a couple of
/// seconds while session state and scheduled-task teardown still write. On the common demo→demo
/// relaunch the new process would otherwise delete `AlvearyDemo/` while the old one still holds an
/// open SQLite handle, which then recreates files inside the wiped tree.
enum DemoStorageHandshake {
    private static let timeout: TimeInterval = 6
    private static let pollInterval: TimeInterval = 0.1

    /// Blocks — bounded — until this is the only Alveary instance running. Called from
    /// `AppRuntimeProfile.makeCurrent()` immediately before `AppStorageProfile.demo()`, which is
    /// before the model container exists, so nothing here is waiting on our own storage.
    static func waitForOtherInstancesToExit() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, otherInstanceIsRunning(bundleIdentifier: bundleIdentifier) {
            Thread.sleep(forTimeInterval: pollInterval)
        }
    }

    private static func otherInstanceIsRunning(bundleIdentifier: String) -> Bool {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { !$0.isTerminated && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }
}
#endif
