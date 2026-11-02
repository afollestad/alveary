import Foundation
import XCTest

@testable import Alveary

// The status menu's pull-requests-needing-review section: its toggle and poll interval.
extension AppSettingsTests {
    func testMenuBarListsPullRequestsNeedingReviewEveryFiveMinutesByDefault() {
        XCTAssertTrue(AppSettings().menuBarShowsPullRequestsNeedingReview)
        XCTAssertEqual(AppSettings().menuBarPullRequestRefreshInterval, .fiveMinutes)
    }

    func testDecodeDefaultsMenuBarPullRequestSettingsWhenFieldsAreMissing() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

        XCTAssertTrue(settings.menuBarShowsPullRequestsNeedingReview)
        XCTAssertEqual(settings.menuBarPullRequestRefreshInterval, .fiveMinutes)
    }

    func testDecodeDefaultsMenuBarPullRequestRefreshIntervalWhenFieldIsInvalid() throws {
        let unsupported = Data(#"{"menuBarPullRequestRefreshInterval":7}"#.utf8)
        let mistyped = Data(#"{"menuBarPullRequestRefreshInterval":"often"}"#.utf8)

        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: unsupported).menuBarPullRequestRefreshInterval, .fiveMinutes)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: mistyped).menuBarPullRequestRefreshInterval, .fiveMinutes)
    }

    func testMenuBarPullRequestRefreshIntervalsPersistAsMinutes() throws {
        var settings = AppSettings()
        settings.menuBarPullRequestRefreshInterval = .fifteenMinutes

        let json = try XCTUnwrap(String(data: JSONEncoder().encode(settings), encoding: .utf8))

        XCTAssertTrue(json.contains(#""menuBarPullRequestRefreshInterval":15"#))
        XCTAssertEqual(MenuBarPullRequestRefreshInterval.fifteenMinutes.duration, .seconds(900))
    }
}
