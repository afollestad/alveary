import XCTest

@testable import Alveary

@MainActor
extension SidebarKeyboardNavigationTests {
    func testShouldNavigateUpOnLeftArrowReturnsTrueForScheduledSelection() {
        XCTAssertTrue(shouldNavigateUpOnLeftArrow(selection: .scheduled, expandedProjects: []))
    }

    func testShouldNavigateDownOnRightArrowReturnsTrueForScheduledSelection() {
        XCTAssertTrue(shouldNavigateDownOnRightArrow(selection: .scheduled, expandedProjects: []))
    }
}
