import Foundation
import XCTest

@testable import Alveary

// Persisted screen tab and filter state: Pull Requests and Scheduled.
extension AppSettingsTests {
    func testDecodeScreenStateDefaultsWhenFieldsAreMissing() throws {
        let json = Data("{}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.pullRequestsSelectedTab, "All")
        // Open-only by default, so "needs my review" cannot fill with merged and closed work.
        XCTAssertEqual(settings.pullRequestsStatusFilter, .open)
        XCTAssertEqual(settings.pullRequestsRepositoryFilters, [])
        XCTAssertEqual(settings.scheduledTasksSelectedTab, "All")
    }

    func testDecodePreservesPullRequestsScreenState() throws {
        let json = Data(#"""
        {
          "pullRequestsSelectedTab": "Reviewing",
          "pullRequestsStatusFilter": "merged",
          "pullRequestsRepositoryFilters": ["octo/alpha", "octo/beta"]
        }
        """#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.pullRequestsSelectedTab, "Reviewing")
        XCTAssertEqual(settings.pullRequestsStatusFilter, .merged)
        XCTAssertEqual(settings.pullRequestsRepositoryFilters, ["octo/alpha", "octo/beta"])
    }

    func testDecodeMigratesTheMultiSelectStatusFilter() throws {
        // One selected status is all single-select can express, so it carries over.
        let single = Data(#"{"pullRequestsStatusFilters":["merged"]}"#.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(AppSettings.self, from: single).pullRequestsStatusFilter,
            .merged
        )
        // A combination and the old "no selection" default both take the new packaged default
        // rather than widening to every status.
        let combination = Data(#"{"pullRequestsStatusFilters":["open","merged"]}"#.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(AppSettings.self, from: combination).pullRequestsStatusFilter,
            .open
        )
        let empty = Data(#"{"pullRequestsStatusFilters":[]}"#.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(AppSettings.self, from: empty).pullRequestsStatusFilter,
            .open
        )
        // Unknown status strings drop out element-wise, leaving one recognized selection.
        let unknown = Data(#"{"pullRequestsStatusFilters":["bogus","draft"]}"#.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(AppSettings.self, from: unknown).pullRequestsStatusFilter,
            .draft
        )
    }

    func testPullRequestsScreenStateRoundTripsThroughCodable() throws {
        var settings = AppSettings()
        settings.pullRequestsSelectedTab = "Authored"
        // `all` has to survive the round trip: it is a real choice, not an unset value.
        settings.pullRequestsStatusFilter = .all
        settings.pullRequestsRepositoryFilters = ["octo/alpha"]

        // The synthesized encoder and the tolerant custom decoder must agree on shape.
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        XCTAssertEqual(decoded.pullRequestsSelectedTab, "Authored")
        XCTAssertEqual(decoded.pullRequestsStatusFilter, .all)
        XCTAssertEqual(decoded.pullRequestsRepositoryFilters, ["octo/alpha"])
    }

    func testDecodeToleratesMalformedPullRequestsScreenState() throws {
        let json = Data(#"{"pullRequestsSelectedTab":7,"pullRequestsStatusFilter":"bogus","theme":"dark"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.pullRequestsSelectedTab, "All")
        XCTAssertEqual(settings.pullRequestsStatusFilter, .open)
        XCTAssertEqual(settings.theme, "dark")
    }

    func testDecodePreservesScheduledTasksSelectedTab() throws {
        let json = Data(#"{"scheduledTasksSelectedTab":"Paused"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.scheduledTasksSelectedTab, "Paused")
    }

    func testDecodeToleratesMalformedScheduledTasksSelectedTab() throws {
        let json = Data(#"{"scheduledTasksSelectedTab":3,"theme":"dark"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.scheduledTasksSelectedTab, "All")
        XCTAssertEqual(settings.theme, "dark")
    }
}
