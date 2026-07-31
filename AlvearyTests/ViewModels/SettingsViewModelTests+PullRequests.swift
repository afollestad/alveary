import XCTest

@testable import Alveary

@MainActor
extension SettingsViewModelTests {
    func testPullRequestsEnabledDefaultsToOn() {
        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService())

        XCTAssertTrue(viewModel.pullRequestsEnabled)
    }

    func testPullRequestsEnabledReadsThroughToTheService() {
        let service = InMemorySettingsService()
        service.update { $0.pullRequestsEnabled = false }
        let viewModel = SettingsViewModel(settingsService: service)

        XCTAssertFalse(viewModel.pullRequestsEnabled)
    }

    func testPullRequestsEnabledWritesThroughToTheService() {
        let service = InMemorySettingsService()
        let viewModel = SettingsViewModel(settingsService: service)

        viewModel.pullRequestsEnabled = false

        XCTAssertFalse(service.current.pullRequestsEnabled)
        XCTAssertFalse(viewModel.pullRequestsEnabled)
    }
}
