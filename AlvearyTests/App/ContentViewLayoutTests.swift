import XCTest

@testable import Alveary

final class ContentViewLayoutTests: XCTestCase {
    func testRightPaneBoundsReserveMainPaneWidth() {
        let bounds = RightPaneWidthPolicy.bounds(availableWidth: 1_000)

        XCTAssertEqual(bounds.lowerBound, AppSettings.supportedDiffViewerWidthRange.lowerBound)
        XCTAssertEqual(
            bounds.upperBound,
            1_000
                - RightPaneWidthPolicy.minimumMainPaneWidth
                - RightPaneWidthPolicy.resizeHandleThickness
        )
    }

    func testRightPaneBoundsNeverDropBelowSupportedLowerBound() {
        let bounds = RightPaneWidthPolicy.bounds(availableWidth: 500)

        XCTAssertEqual(bounds.lowerBound, AppSettings.supportedDiffViewerWidthRange.lowerBound)
        XCTAssertEqual(bounds.upperBound, AppSettings.supportedDiffViewerWidthRange.lowerBound)
    }

    func testRightPaneBoundsNeverExceedSupportedUpperBound() {
        let bounds = RightPaneWidthPolicy.bounds(availableWidth: 2_000)

        XCTAssertEqual(bounds.upperBound, AppSettings.supportedDiffViewerWidthRange.upperBound)
    }

    func testEffectiveRightPaneWidthClampsStoredWidthToAvailableSpace() {
        let width = RightPaneWidthPolicy.effectiveWidth(storedWidth: 960, availableWidth: 1_000)

        XCTAssertEqual(
            width,
            1_000
                - RightPaneWidthPolicy.minimumMainPaneWidth
                - RightPaneWidthPolicy.resizeHandleThickness
        )
    }

    func testEffectiveRightPaneWidthClampsStoredWidthToSupportedLowerBound() {
        let width = RightPaneWidthPolicy.effectiveWidth(storedWidth: 100, availableWidth: 1_000)

        XCTAssertEqual(width, AppSettings.supportedDiffViewerWidthRange.lowerBound)
    }
}
