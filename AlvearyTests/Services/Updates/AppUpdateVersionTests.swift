import XCTest

@testable import Alveary

final class AppUpdateVersionTests: XCTestCase {
    func testParsesPlainAndTaggedVersions() {
        XCTAssertEqual(AppUpdateVersion(string: "0.1.2")?.description, "0.1.2")
        XCTAssertEqual(AppUpdateVersion(string: "v1.2.3")?.description, "1.2.3")
        XCTAssertEqual(AppUpdateVersion(string: "V2.3.4")?.description, "2.3.4")
    }

    func testRejectsNonSemverVersions() {
        XCTAssertNil(AppUpdateVersion(string: "1.2"))
        XCTAssertNil(AppUpdateVersion(string: "1.2.3.4"))
        XCTAssertNil(AppUpdateVersion(string: "1.2.beta"))
        XCTAssertNil(AppUpdateVersion(string: "1.2.3-beta"))
    }

    func testComparesSemverComponentsNumerically() throws {
        let oneNine = try XCTUnwrap(AppUpdateVersion(string: "1.9.9"))
        let oneTen = try XCTUnwrap(AppUpdateVersion(string: "1.10.0"))
        let twoZero = try XCTUnwrap(AppUpdateVersion(string: "2.0.0"))

        XCTAssertLessThan(oneNine, oneTen)
        XCTAssertLessThan(oneTen, twoZero)
        XCTAssertGreaterThan(twoZero, oneNine)
    }
}
