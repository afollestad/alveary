import Foundation
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewTests {
    func testCleanupButtonNeverRendersConfirmAndIconTogether() {
        for isConfirmationChromeVisible in [true, false] {
            for isCollapsing in [true, false] {
                let visibility = sidebarThreadCleanupButtonVisibility(
                    isConfirmationChromeVisible: isConfirmationChromeVisible,
                    isCollapsing: isCollapsing
                )
                XCTAssertFalse(
                    visibility.showsConfirm && visibility.showsIcon,
                    "chromeVisible: \(isConfirmationChromeVisible), collapsing: \(isCollapsing)"
                )
            }
        }
    }

    func testCleanupButtonShowsNeitherContentWhileCollapsing() {
        XCTAssertEqual(
            sidebarThreadCleanupButtonVisibility(isConfirmationChromeVisible: false, isCollapsing: true),
            SidebarThreadCleanupButtonVisibility(showsConfirm: false, showsIcon: false)
        )
    }

    func testCleanupButtonShowsIconOnlyAfterCollapseSettles() {
        XCTAssertEqual(
            sidebarThreadCleanupButtonVisibility(isConfirmationChromeVisible: false, isCollapsing: false),
            SidebarThreadCleanupButtonVisibility(showsConfirm: false, showsIcon: true)
        )
    }

    func testCleanupButtonShowsConfirmWhileArmed() {
        XCTAssertEqual(
            sidebarThreadCleanupButtonVisibility(isConfirmationChromeVisible: true, isCollapsing: false),
            SidebarThreadCleanupButtonVisibility(showsConfirm: true, showsIcon: false)
        )
    }

    func testConfirmingAlwaysCollapsesToHiddenRegardlessOfHover() {
        XCTAssertTrue(sidebarThreadCleanupCollapsesToHidden(forCommit: true, isHovering: true))
        XCTAssertTrue(sidebarThreadCleanupCollapsesToHidden(forCommit: true, isHovering: false))
    }

    func testTimeoutCollapsesToHiddenOnlyWhenHoverHasLeft() {
        XCTAssertFalse(sidebarThreadCleanupCollapsesToHidden(forCommit: false, isHovering: true))
        XCTAssertTrue(sidebarThreadCleanupCollapsesToHidden(forCommit: false, isHovering: false))
    }
}
