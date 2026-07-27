import XCTest

@testable import Alveary

@MainActor
final class AppShotCoordinatorTests: XCTestCase {
    func testAttachableAppIsNilWhileAppShotsAreDisabled() {
        let coordinator = AppShotCoordinator()
        coordinator.start(settingsService: makeSettingsService(appShotsEnabled: false))
        defer { coordinator.stop() }

        XCTAssertNil(coordinator.attachableApp)
    }

    func testRequestCaptureRaisesTheTriggerWhileEnabled() {
        let coordinator = AppShotCoordinator()
        coordinator.start(settingsService: makeSettingsService(appShotsEnabled: true))
        defer { coordinator.stop() }

        let originalTrigger = coordinator.triggerID
        coordinator.requestCapture()

        XCTAssertNotEqual(coordinator.triggerID, originalTrigger)
    }

    func testRequestCaptureIsIgnoredWhileAppShotsAreDisabled() {
        let coordinator = AppShotCoordinator()
        coordinator.start(settingsService: makeSettingsService(appShotsEnabled: false))
        defer { coordinator.stop() }

        let originalTrigger = coordinator.triggerID
        coordinator.requestCapture()

        XCTAssertEqual(coordinator.triggerID, originalTrigger)
    }

    func testRequestCaptureRaisesDistinctTriggersForRepeatedRequests() {
        let coordinator = AppShotCoordinator()
        coordinator.start(settingsService: makeSettingsService(appShotsEnabled: true))
        defer { coordinator.stop() }

        coordinator.requestCapture()
        let firstTrigger = coordinator.triggerID
        coordinator.requestCapture()

        XCTAssertNotEqual(coordinator.triggerID, firstTrigger)
    }

    private func makeSettingsService(appShotsEnabled: Bool) -> InMemorySettingsService {
        var settings = AppSettings()
        settings.appShotsEnabled = appShotsEnabled
        return InMemorySettingsService(current: settings)
    }
}
