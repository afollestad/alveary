import Foundation
import XCTest

@testable import Alveary

@MainActor
extension SettingsServiceTests {
    func testUserDefaultsSettingsServicePreservesStoredOldDefaultFontSizesOnLoad() throws {
        let defaults = try makeDefaults()
        let payload: [String: Any] = [
            "codeFontSize": 13,
            "chatFontSize": 14
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: payload),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertEqual(service.current.codeFontSize, 13)
        XCTAssertEqual(service.current.chatFontSize, 14)
    }
}
