import Foundation
import XCTest

@testable import Alveary

@MainActor
extension SettingsServiceTests {
    /// The key is additive, so settings written before it existed must still load with the
    /// integration on rather than silently hiding the pull-request surfaces.
    func testSettingsWithoutTheKeyKeepPullRequestsEnabled() throws {
        let defaults = try makeDefaults()
        let payload: [String: Any] = [
            "defaultProvider": "claude",
            "branchPrefix": "feature/",
            "rightPaneWidth": 520
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: payload),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertTrue(service.current.pullRequestsEnabled)
    }

    func testStoredDisabledPullRequestsDecodes() throws {
        let defaults = try makeDefaults()
        let payload: [String: Any] = [
            "defaultProvider": "claude",
            "pullRequestsEnabled": false
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: payload),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertFalse(service.current.pullRequestsEnabled)
    }

    func testDisabledPullRequestsPersistsAcrossReloads() throws {
        let defaults = try makeDefaults()
        let service = UserDefaultsSettingsService(defaults: defaults)

        service.update { $0.pullRequestsEnabled = false }

        let reloadedService = UserDefaultsSettingsService(defaults: defaults)
        XCTAssertFalse(reloadedService.current.pullRequestsEnabled)
    }
}
