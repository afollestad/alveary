import Foundation
import XCTest

@testable import Alveary

@MainActor
extension SettingsServiceTests {
    func testFreshInstallUsesFallbackVoiceShortcutWhenPrimaryConflicts() throws {
        let defaults = try makeDefaults()

        let service = UserDefaultsSettingsService(
            defaults: defaults,
            hasEnabledSystemConflict: { $0 == .controlShiftSpace }
        )

        XCTAssertEqual(service.current.voiceInputShortcut, .controlCommandShiftSpace)
        let persistedData = try XCTUnwrap(defaults.data(forKey: UserDefaultsSettingsService.storageKey))
        XCTAssertEqual(
            try JSONDecoder().decode(AppSettings.self, from: persistedData).voiceInputShortcut,
            .controlCommandShiftSpace
        )
    }

    func testFreshInstallLeavesVoiceShortcutUnavailableWhenBothDefaultsConflict() throws {
        let defaults = try makeDefaults()

        let service = UserDefaultsSettingsService(
            defaults: defaults,
            hasEnabledSystemConflict: { shortcut in
                shortcut == .controlShiftSpace || shortcut == .controlCommandShiftSpace
            }
        )

        XCTAssertNil(service.current.voiceInputShortcut)
        let persistedData = try XCTUnwrap(defaults.data(forKey: UserDefaultsSettingsService.storageKey))
        XCTAssertNil(try JSONDecoder().decode(AppSettings.self, from: persistedData).voiceInputShortcut)
    }

    func testLegacyVoiceInputShortcutMigrationUsesFallbackAndPersistsImmediately() throws {
        let defaults = try makeDefaults()
        defaults.set(
            try JSONSerialization.data(withJSONObject: ["theme": "dark"]),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(
            defaults: defaults,
            hasEnabledSystemConflict: { $0 == .controlShiftSpace }
        )
        let persistedData = try XCTUnwrap(defaults.data(forKey: UserDefaultsSettingsService.storageKey))
        let persistedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: persistedData) as? [String: Any])

        XCTAssertEqual(service.current.voiceInputShortcut, .controlCommandShiftSpace)
        XCTAssertEqual(persistedJSON["voiceInputShortcutMigrationCompleted"] as? Bool, true)
        XCTAssertEqual(
            try JSONDecoder().decode(AppSettings.self, from: persistedData).voiceInputShortcut,
            .controlCommandShiftSpace
        )
    }

    func testLegacyVoiceInputShortcutMigrationLeavesShortcutUnavailableWhenBothDefaultsConflict() throws {
        let defaults = try makeDefaults()
        defaults.set(
            try JSONSerialization.data(withJSONObject: ["theme": "dark"]),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(
            defaults: defaults,
            hasEnabledSystemConflict: { shortcut in
                shortcut == .controlShiftSpace || shortcut == .controlCommandShiftSpace
            }
        )

        XCTAssertNil(service.current.voiceInputShortcut)
        let persistedData = try XCTUnwrap(defaults.data(forKey: UserDefaultsSettingsService.storageKey))
        let persistedSettings = try JSONDecoder().decode(AppSettings.self, from: persistedData)
        XCTAssertNil(persistedSettings.voiceInputShortcut)
        XCTAssertTrue(persistedSettings.voiceInputShortcutMigrationCompleted)
    }

    func testLegacyExplicitUnavailableVoiceShortcutIsPreservedDuringMigrationPersistence() throws {
        let defaults = try makeDefaults()
        defaults.set(
            try JSONSerialization.data(withJSONObject: ["voiceInputShortcut": NSNull()]),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(
            defaults: defaults,
            hasEnabledSystemConflict: { _ in false }
        )

        XCTAssertNil(service.current.voiceInputShortcut)
        let persistedData = try XCTUnwrap(defaults.data(forKey: UserDefaultsSettingsService.storageKey))
        let persistedSettings = try JSONDecoder().decode(AppSettings.self, from: persistedData)
        XCTAssertNil(persistedSettings.voiceInputShortcut)
        XCTAssertTrue(persistedSettings.voiceInputShortcutMigrationCompleted)
    }

    func testCompletedVoiceInputShortcutMigrationDoesNotRewriteSettingsOnLoad() throws {
        var settings = AppSettings()
        settings.voiceInputShortcut = nil
        let storedData = try JSONEncoder().encode(settings)
        let defaults = try makeDefaults()
        defaults.set(storedData, forKey: UserDefaultsSettingsService.storageKey)
        let encodeCount = LockedState(0)

        let service = UserDefaultsSettingsService(
            defaults: defaults,
            hasEnabledSystemConflict: { _ in true },
            encode: { settings in
                encodeCount.withLock { $0 += 1 }
                return try JSONEncoder().encode(settings)
            }
        )

        XCTAssertNil(service.current.voiceInputShortcut)
        XCTAssertEqual(encodeCount.withLock { $0 }, 0)
        XCTAssertEqual(defaults.data(forKey: UserDefaultsSettingsService.storageKey), storedData)
    }
}
