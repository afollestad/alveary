import Foundation
import XCTest

@testable import Alveary

// The status menu's pull-requests-needing-review section: its toggle and poll interval.
extension AppSettingsTests {
    func testMenuBarListsPullRequestsNeedingReviewEveryFifteenMinutesByDefault() {
        XCTAssertTrue(AppSettings().menuBarShowsPullRequestsNeedingReview)
        XCTAssertEqual(AppSettings().menuBarPullRequestRefreshInterval, .fifteenMinutes)
    }

    func testDecodeDefaultsMenuBarPullRequestSettingsWhenFieldsAreMissing() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

        XCTAssertTrue(settings.menuBarShowsPullRequestsNeedingReview)
        XCTAssertEqual(settings.menuBarPullRequestRefreshInterval, .fifteenMinutes)
    }

    func testDecodeDefaultsMenuBarPullRequestRefreshIntervalWhenFieldIsInvalid() throws {
        let unsupported = Data(#"{"menuBarPullRequestRefreshInterval":7}"#.utf8)
        let mistyped = Data(#"{"menuBarPullRequestRefreshInterval":"often"}"#.utf8)

        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: unsupported).menuBarPullRequestRefreshInterval, .fifteenMinutes)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: mistyped).menuBarPullRequestRefreshInterval, .fifteenMinutes)
    }

    func testMenuBarPullRequestRefreshIntervalsPersistAsMinutes() throws {
        var settings = AppSettings()
        settings.menuBarPullRequestRefreshInterval = .tenMinutes

        let json = try XCTUnwrap(String(data: JSONEncoder().encode(settings), encoding: .utf8))

        XCTAssertTrue(json.contains(#""menuBarPullRequestRefreshInterval":10"#))
        XCTAssertEqual(MenuBarPullRequestRefreshInterval.tenMinutes.duration, .seconds(600))
    }

    func testPullRequestListFilterAssemblesTheScreensPersistedSelection() {
        var settings = AppSettings()
        settings.pullRequestsStatusFilter = .merged
        settings.pullRequestsRepositoryFilters = ["octo/alpha"]
        settings.pullRequestsShowIgnored = true

        XCTAssertEqual(
            settings.pullRequestListFilter,
            PullRequestListFilter(status: .merged, repositories: ["octo/alpha"], showsIgnored: true)
        )
    }
}
