import Foundation
import XCTest

@testable import Alveary

@MainActor
extension SettingsServiceTests {
    func testUndecodableBlobLoadsDefaultsAndPreservesTheOriginal() throws {
        let defaults = try makeDefaults()
        let corruptData = Data("not json".utf8)
        defaults.set(corruptData, forKey: UserDefaultsSettingsService.storageKey)

        let service = UserDefaultsSettingsService(
            defaults: defaults,
            hasEnabledSystemConflict: { _ in false }
        )

        XCTAssertEqual(service.current, AppSettings())
        XCTAssertEqual(
            defaults.data(forKey: UserDefaultsSettingsService.corruptStorageKey),
            corruptData,
            "The unreadable blob must survive the reset so the failure stays diagnosable"
        )
        let replacementData = try XCTUnwrap(defaults.data(forKey: UserDefaultsSettingsService.storageKey))
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: replacementData), service.current)
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
