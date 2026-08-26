import XCTest

@testable import Alveary

@MainActor
final class TranscriptContentWidthCacheTests: XCTestCase {
    func testStoreIgnoresNonPositiveWidths() {
        TranscriptContentWidthCache.removeAll()
        defer { TranscriptContentWidthCache.removeAll() }

        TranscriptContentWidthCache.store(0)
        XCTAssertNil(TranscriptContentWidthCache.lastKnownWidth)

        TranscriptContentWidthCache.store(-320)
        XCTAssertNil(TranscriptContentWidthCache.lastKnownWidth)
    }

    func testStoreKeepsTheLatestPositiveWidth() {
        TranscriptContentWidthCache.removeAll()
        defer { TranscriptContentWidthCache.removeAll() }

        TranscriptContentWidthCache.store(1208)
        XCTAssertEqual(TranscriptContentWidthCache.lastKnownWidth, 1208)

        // A pre-layout `0` must not clobber the seed; only a real layout may move it.
        TranscriptContentWidthCache.store(0)
        XCTAssertEqual(TranscriptContentWidthCache.lastKnownWidth, 1208)

        TranscriptContentWidthCache.store(900)
        XCTAssertEqual(TranscriptContentWidthCache.lastKnownWidth, 900)
    }
}
