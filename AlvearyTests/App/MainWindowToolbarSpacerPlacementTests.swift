import AppKit
import XCTest

@testable import Alveary

final class MainWindowToolbarSpacerPlacementTests: XCTestCase {
    func testMovesLeadingSpacerBetweenAppItems() throws {
        let result = try XCTUnwrap(move(in: [
            .flexibleSpace,
            .init("system-sidebar"),
            .init(MainWindowToolbarItemID.header),
            .init(MainWindowToolbarItemID.actions)
        ]))

        XCTAssertEqual(result.removeIndex, 0)
        XCTAssertEqual(result.insertIndex, 2)
    }

    func testLeavesSpacerBetweenAppItems() {
        XCTAssertNil(move(in: [
            .init("system-sidebar"),
            .init(MainWindowToolbarItemID.header),
            .flexibleSpace,
            .init(MainWindowToolbarItemID.actions)
        ]))
    }

    func testMovesTrailingSpacerBeforeActions() throws {
        let result = try XCTUnwrap(move(in: [
            .init("system-sidebar"),
            .init(MainWindowToolbarItemID.header),
            .init(MainWindowToolbarItemID.actions),
            .flexibleSpace
        ]))

        XCTAssertEqual(result.removeIndex, 3)
        XCTAssertEqual(result.insertIndex, 2)
    }

    func testRequiresBothAppItems() {
        XCTAssertNil(move(in: [
            .flexibleSpace,
            .init(MainWindowToolbarItemID.header)
        ]))
    }

    private func move(
        in identifiers: [NSToolbarItem.Identifier]
    ) -> (removeIndex: Int, insertIndex: Int)? {
        MainWindowToolbarSpacerPlacement.move(in: identifiers)
    }
}
