import Foundation
import XCTest

@testable import Alveary

@MainActor
extension SettingsServiceTests {
    func testUserDefaultsSettingsServicePersistsOnboardingCompletionAcrossReloads() throws {
        let defaults = try makeDefaults()
        let service = UserDefaultsSettingsService(defaults: defaults)

        service.update {
            $0.hasCompletedOnboarding = true
        }

        let reloadedService = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertTrue(reloadedService.current.hasCompletedOnboarding)
    }

    func testUserDefaultsSettingsServiceDefaultsMissingOnboardingCompletionToFalse() throws {
        let defaults = try makeDefaults()
        defaults.set(
            try JSONSerialization.data(withJSONObject: ["settingsSchemaVersion": AppSettings.currentSettingsSchemaVersion]),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertFalse(service.current.hasCompletedOnboarding)
    }
}
