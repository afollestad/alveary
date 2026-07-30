import Foundation
import XCTest

@testable import Alveary

@MainActor
extension SettingsServiceTests {
    /// The key is additive, so settings written before it existed must still load with the row
    /// visible rather than silently hiding the only entry point to the Pull Requests screen.
    func testSettingsWithoutTheKeyKeepPullRequestsVisible() throws {
        let defaults = try makeDefaults()
        let payload: [String: Any] = [
            "defaultProvider": "claude",
            "branchPrefix": "feature/",
            "pullRequestsPaneWidth": 520
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: payload),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertTrue(service.current.showsPullRequestsInSidebar)
    }

    func testStoredHiddenPullRequestsRowDecodes() throws {
        let defaults = try makeDefaults()
        let payload: [String: Any] = [
            "defaultProvider": "claude",
            "showsPullRequestsInSidebar": false
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: payload),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertFalse(service.current.showsPullRequestsInSidebar)
    }

    func testHiddenPullRequestsRowPersistsAcrossReloads() throws {
        let defaults = try makeDefaults()
        let service = UserDefaultsSettingsService(defaults: defaults)

        service.update { $0.showsPullRequestsInSidebar = false }

        let reloadedService = UserDefaultsSettingsService(defaults: defaults)
        XCTAssertFalse(reloadedService.current.showsPullRequestsInSidebar)
    }
}
