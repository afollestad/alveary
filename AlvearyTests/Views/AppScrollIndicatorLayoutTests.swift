import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppScrollIndicatorLayoutTests: XCTestCase {
    /// The clearance is repo-owned so layout cannot drift between a developer's
    /// macOS and CI's, but it is only correct while it exceeds the lane the
    /// system actually hit-tests by the measured grab-slop margin: controls 3pt
    /// clear of the lane still dropped clicks while 11pt clear never did. An OS
    /// that widens the lane should fail here with a clear message instead of
    /// quietly dropping clicks again.
    func testInteractiveTrailingClearanceExceedsTheOverlayLaneByTheMeasuredSlop() {
        let lane = ceil(NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay))

        XCTAssertGreaterThanOrEqual(AppScrollIndicatorLayout.interactiveTrailingClearance, lane + 11)
    }
}
