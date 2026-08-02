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

    /// Auto-linking is opt-in, and the prompt suppression it pairs with only ever
    /// turns on from the transcript's `Never` action.
    func testAutomaticLinkingAndPromptSuppressionDefaultToOff() throws {
        let service = UserDefaultsSettingsService(defaults: try makeDefaults())

        XCTAssertFalse(service.current.automaticallyLinkPullRequests)
        XCTAssertFalse(service.current.suppressPullRequestLinkPrompts)
    }

    func testSettingsWithoutTheAutomaticLinkingKeysDecodeToTheDefaults() throws {
        let defaults = try makeDefaults()
        let payload: [String: Any] = [
            "defaultProvider": "claude",
            "pullRequestsEnabled": true
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: payload),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertFalse(service.current.automaticallyLinkPullRequests)
        XCTAssertFalse(service.current.suppressPullRequestLinkPrompts)
    }

    func testStoredAutomaticLinkingAndSuppressionDecode() throws {
        let defaults = try makeDefaults()
        let payload: [String: Any] = [
            "defaultProvider": "claude",
            "automaticallyLinkPullRequests": true,
            "suppressPullRequestLinkPrompts": true
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: payload),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertTrue(service.current.automaticallyLinkPullRequests)
        XCTAssertTrue(service.current.suppressPullRequestLinkPrompts)
    }

    func testAutomaticLinkingAndSuppressionPersistAcrossReloads() throws {
        let defaults = try makeDefaults()
        let service = UserDefaultsSettingsService(defaults: defaults)

        service.update {
            $0.automaticallyLinkPullRequests = true
            $0.suppressPullRequestLinkPrompts = true
        }

        let reloadedService = UserDefaultsSettingsService(defaults: defaults)
        XCTAssertTrue(reloadedService.current.automaticallyLinkPullRequests)
        XCTAssertTrue(reloadedService.current.suppressPullRequestLinkPrompts)
    }
}
