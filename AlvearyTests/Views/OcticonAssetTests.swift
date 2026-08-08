import AppKit
import XCTest

@testable import Alveary

/// A missing octicon asset is invisible to the compiler and nearly invisible on
/// screen — `Image` draws an empty frame and `NSImage(named:)` returns nil — so
/// a renamed or deleted imageset would otherwise ship as a blank glyph. Full
/// baselines cannot catch it either: a 16pt glyph is well under the 1% pixel
/// budget `assertMacSnapshot` allows.
@MainActor
final class OcticonAssetTests: XCTestCase {
    func testEveryOcticonResolvesFromTheAssetCatalog() {
        for octicon in Octicon.allCases {
            XCTAssertNotNil(
                NSImage(named: octicon.assetName),
                "\(octicon) names a missing asset: \(octicon.assetName)"
            )
        }
    }

    /// The case name promises the artwork's canvas, and call sites pick between
    /// the 16 and 24 variants on that promise. Pointing a `…16` case at 24px
    /// artwork would silently make every mixed row render thin.
    func testCaseNamesMatchTheArtworkCanvas() {
        for octicon in Octicon.allCases {
            let name = String(describing: octicon)
            guard let expected = name.hasSuffix("16") ? 16.0 : name.hasSuffix("24") ? 24.0 : nil else {
                XCTFail("\(name) does not declare its canvas; end the case name in 16 or 24")
                continue
            }
            guard let image = NSImage(named: octicon.assetName) else {
                continue  // Already reported by the resolution test.
            }
            XCTAssertEqual(image.size.width, expected, accuracy: 0.5, "\(name) width")
            XCTAssertEqual(image.size.height, expected, accuracy: 0.5, "\(name) height")
        }
    }

    /// Two cases pointing at one asset would make the 16/24 split a lie.
    func testAssetNamesAreUnique() {
        let names = Octicon.allCases.map(\.assetName)
        XCTAssertEqual(Set(names).count, names.count, "duplicate asset names in Octicon")
    }
}
