import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewTests {
    // MARK: - Inline name commit values

    func testNewSectionNameCommitsTrimmedAndCancelsWhenEmpty() {
        XCTAssertEqual(sidebarNewSectionNameCommitValue("  Research  "), "Research")
        XCTAssertNil(sidebarNewSectionNameCommitValue(""))
        XCTAssertNil(sidebarNewSectionNameCommitValue("   \n "))
    }

    /// A rename that changes nothing cancels, so committing always means the user edited the name.
    func testSectionRenameCancelsWhenEmptyOrUnchanged() {
        XCTAssertEqual(
            sidebarSectionRenameCommitValue(initialValue: "Research", submittedValue: " Reading "),
            "Reading"
        )
        XCTAssertNil(sidebarSectionRenameCommitValue(initialValue: "Research", submittedValue: "Research"))
        XCTAssertNil(sidebarSectionRenameCommitValue(initialValue: "Research", submittedValue: "  Research  "))
        XCTAssertNil(sidebarSectionRenameCommitValue(initialValue: "Research", submittedValue: "   "))
    }

    // MARK: - Empty-area hit region

    func testEmptyAreaIsOnlyTheRegionBelowEveryPublishedRow() {
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 400)],
            .projectsHeader: [CGRect(x: 0, y: 40, width: 200, height: 24)],
            .tasksHeader: [CGRect(x: 0, y: 100, width: 200, height: 24)],
            .tasksTerminal: [CGRect(x: 0, y: 130, width: 200, height: 24)]
        ]

        XCTAssertTrue(sidebarEmptyAreaContainsPoint(CGPoint(x: 100, y: 200), geometry: geometry))
        // Inside a row, and in the gap between two rows, both belong to the list itself.
        XCTAssertFalse(sidebarEmptyAreaContainsPoint(CGPoint(x: 100, y: 50), geometry: geometry))
        XCTAssertFalse(sidebarEmptyAreaContainsPoint(CGPoint(x: 100, y: 80), geometry: geometry))
        // Outside the viewport entirely.
        XCTAssertFalse(sidebarEmptyAreaContainsPoint(CGPoint(x: 100, y: 500), geometry: geometry))
        XCTAssertFalse(sidebarEmptyAreaContainsPoint(CGPoint(x: 300, y: 200), geometry: geometry))
    }

    /// The click arrives in overlay coordinates while the rows publish in the drag named space;
    /// the same `sidebarDragLocationInNamedSpace` conversion pointer drags use must apply, or an
    /// inset viewport shifts the empty-area boundary by its origin.
    func testEmptyAreaConvertsTheClickIntoTheNamedSpaceLikeDragsDo() {
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 14, y: 52, width: 200, height: 400)],
            .tasksTerminal: [CGRect(x: 14, y: 60, width: 200, height: 24)]
        ]

        // Monitor (100, 60) → named (114, 112), below the last row's maxY of 84.
        XCTAssertTrue(sidebarEmptyAreaContainsPoint(CGPoint(x: 100, y: 60), geometry: geometry))
        // Monitor (100, 20) → named (114, 72), still inside the last row's band.
        XCTAssertFalse(sidebarEmptyAreaContainsPoint(CGPoint(x: 100, y: 20), geometry: geometry))
    }

    /// The `.viewport` frame is the list itself, so it must never count as content — otherwise
    /// nothing below the last row would ever qualify.
    func testEmptyAreaIgnoresTheViewportWhenMeasuringContent() {
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 400)]
        ]

        XCTAssertTrue(sidebarEmptyAreaContainsPoint(CGPoint(x: 100, y: 390), geometry: geometry))
    }

    func testEmptyAreaRejectsEveryPointWithoutViewportGeometry() {
        XCTAssertFalse(sidebarEmptyAreaContainsPoint(CGPoint(x: 100, y: 200), geometry: [:]))
    }

    /// `sidebarEmptyAreaContainsPoint` compares against frames measured in a SwiftUI coordinate
    /// space, so the reporting view has to hand back a top-left-origin point. An unflipped `NSView`
    /// mirrors y, which put every empty-area click somewhere near the top of the list and made the
    /// "New Section..." menu unreachable.
    func testSecondaryClickTargetReportsTopLeftOriginPoints() {
        XCTAssertTrue(SecondaryClickTargetView().isFlipped)
    }

    // MARK: - Section header context menu

    func testSectionContextMenuWithholdsRenameWhileAnotherInlineEditIsActive() {
        XCTAssertEqual(sidebarSectionContextMenuItems(isInlineEditingActive: false), [.rename, .remove])
        XCTAssertEqual(sidebarSectionContextMenuItems(isInlineEditingActive: true), [.remove])
    }

    // MARK: - Removal dialog copy

    func testRemoveSectionConfirmationNamesTheSectionAndPromisesThreadsSurvive() {
        let message = sidebarRemoveSectionConfirmationMessage(sectionName: "Research")

        XCTAssertTrue(message.contains("Research"), message)
        XCTAssertTrue(message.contains("Tasks"), message)
        XCTAssertTrue(message.contains("not deleted"), message)
    }

    // MARK: - Placeholder

    func testEmptyCustomSectionPlaceholderReadsAsEmptyRatherThanBroken() {
        XCTAssertEqual(sidebarCustomSectionPlaceholderLabel(), "No threads")
    }
}
