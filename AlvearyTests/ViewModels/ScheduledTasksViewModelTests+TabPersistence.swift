import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTasksViewModelTests {
    func testRestoresPersistedTab() throws {
        let fixture = try ScheduledTasksViewModelFixture(configureSettings: {
            $0.scheduledTasksSelectedTab = "Paused"
        })

        XCTAssertEqual(fixture.viewModel.selectedFilter, .paused)
    }

    func testInvalidPersistedTabFallsBackToAll() throws {
        let fixture = try ScheduledTasksViewModelFixture(configureSettings: {
            $0.scheduledTasksSelectedTab = "Bogus"
        })

        XCTAssertEqual(fixture.viewModel.selectedFilter, .all)
    }

    func testSelectFilterPersistsTabAndSkipsRedundantWrites() throws {
        let fixture = try ScheduledTasksViewModelFixture()

        fixture.viewModel.selectFilter(.active)

        XCTAssertEqual(fixture.viewModel.selectedFilter, .active)
        XCTAssertEqual(fixture.settingsService.current.scheduledTasksSelectedTab, "Active")

        let updateCount = fixture.settingsService.updateCount
        fixture.viewModel.selectFilter(.active)
        XCTAssertEqual(fixture.settingsService.updateCount, updateCount)
    }
}
