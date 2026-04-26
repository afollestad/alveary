import XCTest

@testable import Alveary

final class ContentViewLayoutTests: XCTestCase {
    func testDiffViewerBoundsReserveMiddlePaneWidth() {
        let bounds = ContentDiffViewerWidthPolicy.bounds(availableWidth: 1_000)

        XCTAssertEqual(bounds.lowerBound, AppSettings.supportedDiffViewerWidthRange.lowerBound)
        XCTAssertEqual(
            bounds.upperBound,
            1_000
                - ContentDiffViewerWidthPolicy.minimumMiddlePaneWidth
                - ContentDiffViewerWidthPolicy.resizeHandleThickness
        )
    }

    func testDiffViewerBoundsNeverDropBelowSupportedLowerBound() {
        let bounds = ContentDiffViewerWidthPolicy.bounds(availableWidth: 500)

        XCTAssertEqual(bounds.lowerBound, AppSettings.supportedDiffViewerWidthRange.lowerBound)
        XCTAssertEqual(bounds.upperBound, AppSettings.supportedDiffViewerWidthRange.lowerBound)
    }

    func testDiffViewerBoundsNeverExceedSupportedUpperBound() {
        let bounds = ContentDiffViewerWidthPolicy.bounds(availableWidth: 2_000)

        XCTAssertEqual(bounds.upperBound, AppSettings.supportedDiffViewerWidthRange.upperBound)
    }

    func testEffectiveDiffViewerWidthClampsStoredWidthToAvailableSpace() {
        let width = ContentDiffViewerWidthPolicy.effectiveWidth(storedWidth: 960, availableWidth: 1_000)

        XCTAssertEqual(
            width,
            1_000
                - ContentDiffViewerWidthPolicy.minimumMiddlePaneWidth
                - ContentDiffViewerWidthPolicy.resizeHandleThickness
        )
    }

    func testEffectiveDiffViewerWidthClampsStoredWidthToSupportedLowerBound() {
        let width = ContentDiffViewerWidthPolicy.effectiveWidth(storedWidth: 100, availableWidth: 1_000)

        XCTAssertEqual(width, AppSettings.supportedDiffViewerWidthRange.lowerBound)
    }
}
