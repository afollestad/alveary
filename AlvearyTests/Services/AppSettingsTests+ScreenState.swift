import Foundation
import XCTest

@testable import Alveary

// Persisted screen tab and filter state: Pull Requests and Scheduled.
extension AppSettingsTests {
    func testDecodeScreenStateDefaultsWhenFieldsAreMissing() throws {
        let json = Data("{}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.pullRequestsSelectedTab, "All")
        XCTAssertEqual(settings.pullRequestsStatusFilters, [])
        XCTAssertEqual(settings.pullRequestsRepositoryFilters, [])
        XCTAssertEqual(settings.scheduledTasksSelectedTab, "All")
    }

    func testDecodePreservesPullRequestsScreenState() throws {
        let json = Data(#"""
        {
          "pullRequestsSelectedTab": "Reviewing",
          "pullRequestsStatusFilters": ["open", "bogus", "merged"],
          "pullRequestsRepositoryFilters": ["octo/alpha", "octo/beta"]
        }
        """#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.pullRequestsSelectedTab, "Reviewing")
        // Unknown status strings drop out instead of failing or polluting the set.
        XCTAssertEqual(settings.pullRequestsStatusFilters, [.open, .merged])
        XCTAssertEqual(settings.pullRequestsRepositoryFilters, ["octo/alpha", "octo/beta"])
    }

    func testPullRequestsScreenStateRoundTripsThroughCodable() throws {
        var settings = AppSettings()
        settings.pullRequestsSelectedTab = "Authored"
        settings.pullRequestsStatusFilters = [.draft, .closed]
        settings.pullRequestsRepositoryFilters = ["octo/alpha"]

        // The synthesized encoder and the tolerant custom decoder must agree on shape.
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        XCTAssertEqual(decoded.pullRequestsSelectedTab, "Authored")
        XCTAssertEqual(decoded.pullRequestsStatusFilters, [.draft, .closed])
        XCTAssertEqual(decoded.pullRequestsRepositoryFilters, ["octo/alpha"])
    }

    func testDecodeToleratesMalformedPullRequestsScreenState() throws {
        let json = Data(#"{"pullRequestsSelectedTab":7,"pullRequestsStatusFilters":"open","theme":"dark"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.pullRequestsSelectedTab, "All")
        XCTAssertEqual(settings.pullRequestsStatusFilters, [])
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
