import Foundation
import XCTest

@testable import Alveary

@MainActor
extension SettingsServiceTests {
    func testUndecodableBlobLoadsDefaultsAndPreservesTheOriginal() throws {
        let defaults = try makeDefaults()
        let corruptData = Data("not json".utf8)
        defaults.set(corruptData, forKey: UserDefaultsSettingsService.storageKey)

        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertEqual(service.current.hasCompletedOnboarding, AppSettings().hasCompletedOnboarding)
        XCTAssertEqual(
            defaults.data(forKey: UserDefaultsSettingsService.corruptStorageKey),
            corruptData,
            "The unreadable blob must survive the reset so the failure stays diagnosable"
        )
        XCTAssertNotEqual(defaults.data(forKey: UserDefaultsSettingsService.storageKey), corruptData)
    }

    func testFirstLaunchWritesNoCorruptBlob() throws {
        let defaults = try makeDefaults()

        _ = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertNil(defaults.data(forKey: UserDefaultsSettingsService.corruptStorageKey))
    }

    func testDecodableBlobWritesNoCorruptBlob() throws {
        let defaults = try makeDefaults()
        defaults.set(
            try JSONSerialization.data(withJSONObject: ["settingsSchemaVersion": AppSettings.currentSettingsSchemaVersion]),
            forKey: UserDefaultsSettingsService.storageKey
        )

        _ = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertNil(defaults.data(forKey: UserDefaultsSettingsService.corruptStorageKey))
    }
}
