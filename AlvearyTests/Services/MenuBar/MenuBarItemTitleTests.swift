import XCTest

@testable import Alveary

final class MenuBarItemTitleTests: XCTestCase {
    func testTruncatesLongTitlesAndCollapsesWhitespace() {
        XCTAssertEqual(MenuBarItemTitle.truncated("Fix   the\nflaky test"), "Fix the flaky test")

        let long = String(repeating: "a", count: 80)
        let truncated = MenuBarItemTitle.truncated(long)

        XCTAssertTrue(truncated.hasSuffix("…"))
        XCTAssertLessThan(truncated.count, long.count)
    }
}
