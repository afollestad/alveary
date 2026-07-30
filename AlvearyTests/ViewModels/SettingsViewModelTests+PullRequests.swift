import XCTest

@testable import Alveary

@MainActor
extension SettingsViewModelTests {
    func testShowsPullRequestsInSidebarDefaultsToVisible() {
        let viewModel = SettingsViewModel(settingsService: InMemorySettingsService())

        XCTAssertTrue(viewModel.showsPullRequestsInSidebar)
    }

    func testShowsPullRequestsInSidebarReadsThroughToTheService() {
        let service = InMemorySettingsService()
        service.update { $0.showsPullRequestsInSidebar = false }
        let viewModel = SettingsViewModel(settingsService: service)

        XCTAssertFalse(viewModel.showsPullRequestsInSidebar)
    }

    func testShowsPullRequestsInSidebarWritesThroughToTheService() {
        let service = InMemorySettingsService()
        let viewModel = SettingsViewModel(settingsService: service)

        viewModel.showsPullRequestsInSidebar = false

        XCTAssertFalse(service.current.showsPullRequestsInSidebar)
        XCTAssertFalse(viewModel.showsPullRequestsInSidebar)
    }
}
