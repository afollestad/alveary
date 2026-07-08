import Foundation
import XCTest

@testable import Alveary

extension AppSettingsTests {
    func testDefaultOnboardingCompletionIsFalse() {
        XCTAssertFalse(AppSettings().hasCompletedOnboarding)
    }

    func testDecodeDefaultsOnboardingCompletionWhenFieldIsMissing() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

        XCTAssertFalse(settings.hasCompletedOnboarding)
    }

    func testEncodeIncludesOnboardingCompletion() throws {
        let encoded = try JSONEncoder().encode(AppSettings(hasCompletedOnboarding: true))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(object["hasCompletedOnboarding"] as? Bool, true)
    }
}
