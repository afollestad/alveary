import XCTest

@testable import Alveary

@MainActor
final class AppShotCoordinatorTests: XCTestCase {
    func testAttachableAppIsNilWhileAppShotsAreDisabled() {
        let coordinator = makeCoordinator()
        coordinator.start(settingsService: makeSettingsService(appShotsEnabled: false))
        defer { coordinator.stop() }

        XCTAssertNil(coordinator.attachableApp)
    }

    func testRequestCaptureRaisesTheTriggerWhileEnabled() {
        let coordinator = makeCoordinator()
        coordinator.start(settingsService: makeSettingsService(appShotsEnabled: true))
        defer { coordinator.stop() }

        coordinator.requestCapture()

        XCTAssertNotNil(coordinator.pendingTriggerID)
    }

    func testRequestCaptureIsIgnoredWhileAppShotsAreDisabled() {
        let coordinator = makeCoordinator()
        coordinator.start(settingsService: makeSettingsService(appShotsEnabled: false))
        defer { coordinator.stop() }

        coordinator.requestCapture()

        XCTAssertNil(coordinator.pendingTriggerID)
    }

    func testRequestCaptureRaisesDistinctTriggersForRepeatedRequests() {
        let coordinator = makeCoordinator()
        coordinator.start(settingsService: makeSettingsService(appShotsEnabled: true))
        defer { coordinator.stop() }

        coordinator.requestCapture()
        let firstTrigger = coordinator.pendingTriggerID
        coordinator.requestCapture()

        XCTAssertNotEqual(coordinator.pendingTriggerID, firstTrigger)
    }

    /// The root drains a trigger by id, so a drain racing a fresh press cannot swallow the newer one.
    func testClearingAStaleTriggerLeavesTheCurrentOnePending() throws {
        let coordinator = makeCoordinator()
        coordinator.start(settingsService: makeSettingsService(appShotsEnabled: true))
        defer { coordinator.stop() }

        coordinator.requestCapture()
        coordinator.clearPendingTrigger(UUID())

        let pendingTrigger = try XCTUnwrap(coordinator.pendingTriggerID)
        coordinator.clearPendingTrigger(pendingTrigger)

        XCTAssertNil(coordinator.pendingTriggerID)
    }

    /// A press with the window closed has nowhere to route until the scene exists; one with a
    /// window present must not steal focus from the app being captured.
    func testTriggerAsksForTheWindowOnlyWhenTheSceneIsClosed() {
        let recorder = MainWindowRequestRecorder()
        let coordinator = makeCoordinator(presentMainWindowIfClosed: recorder.record)
        coordinator.start(settingsService: makeSettingsService(appShotsEnabled: true))
        defer { coordinator.stop() }

        coordinator.requestCapture()

        XCTAssertEqual(recorder.count, 1)
    }

    func testDisabledTriggerDoesNotAskForTheWindow() {
        let recorder = MainWindowRequestRecorder()
        let coordinator = makeCoordinator(presentMainWindowIfClosed: recorder.record)
        coordinator.start(settingsService: makeSettingsService(appShotsEnabled: false))
        defer { coordinator.stop() }

        coordinator.requestCapture()

        XCTAssertEqual(recorder.count, 0)
    }

    /// Suppression covers the system-wide registration only — everything else still runs, or the
    /// hosted lifecycle would be inert rather than merely quiet.
    func testSuppressingTheGlobalShortcutLeavesTheRestOfTheLifecycleRunning() {
        let coordinator = makeCoordinator()
        coordinator.start(settingsService: makeSettingsService(appShotsEnabled: true))
        defer { coordinator.stop() }

        XCTAssertFalse(coordinator.hasInstalledShortcutMonitors)

        coordinator.requestCapture()

        XCTAssertNotNil(coordinator.pendingTriggerID)
    }

    /// The one test that registers for real, so the suppression above is proven to be a
    /// difference rather than a flag nothing reads. The `defer` matters more than usual: a failed
    /// assertion here would otherwise hold ⌃⇧S away from the developer's Alveary for the whole
    /// run, and `stop()` is idempotent, so the explicit call below is still the assertion's
    /// subject.
    func testAnUnsuppressedCoordinatorInstallsAndReleasesTheShortcut() {
        let coordinator = AppShotCoordinator()
        coordinator.start(settingsService: makeSettingsService(appShotsEnabled: true))
        defer { coordinator.stop() }

        XCTAssertTrue(coordinator.hasInstalledShortcutMonitors)

        coordinator.stop()

        XCTAssertFalse(coordinator.hasInstalledShortcutMonitors)
    }

    /// The shortcut's registration is system-wide, so a test run that installed it would take
    /// ⌃⇧S away from the developer's running Alveary. Only the seam's own test installs.
    private func makeCoordinator(
        presentMainWindowIfClosed: @escaping @MainActor () -> Void = {}
    ) -> AppShotCoordinator {
        AppShotCoordinator(
            installsGlobalShortcut: false,
            presentMainWindowIfClosed: presentMainWindowIfClosed
        )
    }

    private func makeSettingsService(appShotsEnabled: Bool) -> InMemorySettingsService {
        var settings = AppSettings()
        settings.appShotsEnabled = appShotsEnabled
        return InMemorySettingsService(current: settings)
    }
}

@MainActor
private final class MainWindowRequestRecorder {
    private(set) var count = 0

    func record() {
        count += 1
    }
}
