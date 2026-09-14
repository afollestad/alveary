import XCTest

@testable import Alveary

final class ProjectSettingsIconNavigationTests: XCTestCase {
    func testHorizontalAndTabTraversalWrapAcrossThePalette() {
        XCTAssertEqual(ProjectSettingsIconNavigation.destination(from: 13, direction: .next, count: 14), 0)
        XCTAssertEqual(ProjectSettingsIconNavigation.destination(from: 0, direction: .previous, count: 14), 13)
        XCTAssertEqual(ProjectSettingsIconNavigation.destination(from: 2, direction: .next, count: 14), 3)
    }

    func testVerticalTraversalStaysInTheColumnAcrossAnIncompleteFinalRow() {
        XCTAssertEqual(ProjectSettingsIconNavigation.destination(from: 11, direction: .downward, count: 14), 2)
        XCTAssertEqual(ProjectSettingsIconNavigation.destination(from: 2, direction: .upward, count: 14), 11)
        XCTAssertEqual(ProjectSettingsIconNavigation.destination(from: 10, direction: .downward, count: 14), 13)
        XCTAssertEqual(ProjectSettingsIconNavigation.destination(from: 1, direction: .upward, count: 14), 13)
        XCTAssertEqual(ProjectSettingsIconNavigation.destination(from: 13, direction: .upward, count: 14), 10)
    }
}
