import XCTest

@testable import Alveary

@MainActor
extension SettingsViewModelTests {
    func testLaunchAtStartupReadsTheRegistrationOnInit() {
        let service = RecordingLaunchAtStartupService(status: .enabled)
        let viewModel = makeLaunchAtStartupViewModel(service: service)

        XCTAssertTrue(viewModel.launchAtStartup)
        XCTAssertEqual(viewModel.launchAtStartupStatus, .enabled)
    }

    func testSetLaunchAtStartupRegistersAndReadsBack() {
        let service = RecordingLaunchAtStartupService(status: .disabled)
        let viewModel = makeLaunchAtStartupViewModel(service: service)

        viewModel.setLaunchAtStartup(true)

        XCTAssertEqual(service.setEnabledCalls, [true])
        XCTAssertTrue(viewModel.launchAtStartup)
        XCTAssertFalse(viewModel.didFailToChangeLaunchAtStartup)
    }

    func testSetLaunchAtStartupUnregistersWhenSwitchedOff() {
        let service = RecordingLaunchAtStartupService(status: .enabled)
        let viewModel = makeLaunchAtStartupViewModel(service: service)

        viewModel.setLaunchAtStartup(false)

        XCTAssertEqual(service.setEnabledCalls, [false])
        XCTAssertFalse(viewModel.launchAtStartup)
        XCTAssertNil(viewModel.launchAtStartupHint)
    }

    func testSetLaunchAtStartupKeepsTheSwitchOffWhenTheSystemRefuses() {
        let service = RecordingLaunchAtStartupService(status: .disabled)
        service.setEnabledError = RecordingLaunchAtStartupService.Failure()
        let viewModel = makeLaunchAtStartupViewModel(service: service)

        viewModel.setLaunchAtStartup(true)

        XCTAssertFalse(viewModel.launchAtStartup)
        XCTAssertTrue(viewModel.didFailToChangeLaunchAtStartup)
    }

    func testRefreshLaunchAtStartupStatusPicksUpAnExternalChange() {
        let service = RecordingLaunchAtStartupService(status: .enabled)
        let viewModel = makeLaunchAtStartupViewModel(service: service)

        service.status = .requiresApproval
        viewModel.refreshLaunchAtStartupStatus()

        XCTAssertFalse(viewModel.launchAtStartup)
        XCTAssertEqual(viewModel.launchAtStartupStatus, .requiresApproval)
    }

    func testLaunchAtStartupHintIsAbsentWhileTheRegistrationAgreesWithTheSwitch() {
        let enabled = makeLaunchAtStartupViewModel(service: RecordingLaunchAtStartupService(status: .enabled))
        let disabled = makeLaunchAtStartupViewModel(service: RecordingLaunchAtStartupService(status: .disabled))

        XCTAssertNil(enabled.launchAtStartupHint)
        XCTAssertNil(disabled.launchAtStartupHint)
    }

    func testLaunchAtStartupHintNamesSystemSettingsWhileTheItemAwaitsApproval() {
        let viewModel = makeLaunchAtStartupViewModel(service: RecordingLaunchAtStartupService(status: .requiresApproval))

        XCTAssertEqual(
            viewModel.launchAtStartupHint,
            "Alveary's login item is switched off in System Settings, so it will not launch at startup yet."
        )
    }

    func testLaunchAtStartupHintReportsARefusedChange() {
        let service = RecordingLaunchAtStartupService(status: .disabled)
        service.setEnabledError = RecordingLaunchAtStartupService.Failure()
        let viewModel = makeLaunchAtStartupViewModel(service: service)

        viewModel.setLaunchAtStartup(true)

        XCTAssertEqual(
            viewModel.launchAtStartupHint,
            "macOS did not accept the change. You can add or remove Alveary in System Settings."
        )
    }

    func testRefreshLaunchAtStartupStatusClearsAFailureOnceTheItemIsEnabled() {
        let service = RecordingLaunchAtStartupService(status: .disabled)
        service.setEnabledError = RecordingLaunchAtStartupService.Failure()
        let viewModel = makeLaunchAtStartupViewModel(service: service)
        viewModel.setLaunchAtStartup(true)

        service.status = .enabled
        viewModel.refreshLaunchAtStartupStatus()

        XCTAssertFalse(viewModel.didFailToChangeLaunchAtStartup)
    }

    /// The packaged default must never touch the developer's real login items.
    func testLaunchAtStartupDefaultsToTheInertService() {
        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService())

        viewModel.setLaunchAtStartup(true)

        XCTAssertFalse(viewModel.launchAtStartup)
        XCTAssertFalse(viewModel.didFailToChangeLaunchAtStartup)
    }

    private func makeLaunchAtStartupViewModel(service: RecordingLaunchAtStartupService) -> SettingsViewModel {
        SettingsViewModel(
            settingsService: InMemorySettingsService(),
            launchAtStartupService: service
        )
    }
}

@MainActor
private final class RecordingLaunchAtStartupService: LaunchAtStartupService {
    struct Failure: Error {}

    var status: LaunchAtStartupStatus
    var setEnabledError: Error?
    private(set) var setEnabledCalls: [Bool] = []

    init(status: LaunchAtStartupStatus) {
        self.status = status
    }

    func setEnabled(_ isEnabled: Bool) throws {
        setEnabledCalls.append(isEnabled)
        if let setEnabledError {
            throw setEnabledError
        }
        status = isEnabled ? .enabled : .disabled
    }
}
