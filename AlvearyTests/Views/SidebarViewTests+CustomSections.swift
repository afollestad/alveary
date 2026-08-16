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

    // MARK: - Section header hit region and highlight

    /// An expanded section's outline runs from its header's title row through its last row, so a
    /// right-click lights exactly what a dragged thread would drop into.
    func testSecondaryClickOnAnExpandedSectionHeaderHighlightsItsWholeSection() {
        let highlight = sidebarSecondaryClickSectionHighlight(
            CGPoint(x: 100, y: 110),
            geometry: Self.sectionHighlightGeometry
        )

        XCTAssertEqual(highlight?.sectionID, "research")
        XCTAssertEqual(
            highlight?.frame,
            CGRect(x: 0, y: 100, width: 200, height: 54)
                .insetBy(dx: 0, dy: -SidebarDropTargetingMetrics.containerOutset)
        )
    }

    /// A collapsed section unmounts its rows, so nothing publishes `.customSectionTerminal` and
    /// the outline falls back to the header row alone.
    func testSecondaryClickOnACollapsedSectionHeaderHighlightsTheHeaderAlone() {
        let highlight = sidebarSecondaryClickSectionHighlight(
            CGPoint(x: 100, y: 210),
            geometry: Self.sectionHighlightGeometry
        )

        XCTAssertEqual(highlight?.sectionID, "reading")
        XCTAssertEqual(
            highlight?.frame,
            CGRect(x: 0, y: 200, width: 200, height: 24)
                .insetBy(dx: 0, dy: -SidebarDropTargetingMetrics.containerOutset)
        )
    }

    /// The header publishes its visible title row with `inlineHeaderTotalTopPadding` excluded, so
    /// the divider's breathing room above it is not the header — which is the whole bug: a
    /// `contextMenu` highlighted the padded frame and outlined the divider with it.
    func testSecondaryClickAboveASectionHeaderIsNotTheHeader() {
        XCTAssertNil(
            sidebarSecondaryClickSectionHighlight(
                CGPoint(x: 100, y: 90),
                geometry: Self.sectionHighlightGeometry
            )
        )
    }

    /// Built-in headers have no menu, so their frames must never resolve to a highlight; neither
    /// may a member row, the empty area, or a sidebar that has published nothing yet.
    func testSecondaryClickOutsideACustomSectionHeaderHighlightsNothing() {
        for point in [CGPoint(x: 100, y: 50), CGPoint(x: 100, y: 140), CGPoint(x: 100, y: 350)] {
            XCTAssertNil(
                sidebarSecondaryClickSectionHighlight(point, geometry: Self.sectionHighlightGeometry),
                "\(point)"
            )
        }
        XCTAssertNil(sidebarSecondaryClickSectionHighlight(CGPoint(x: 100, y: 110), geometry: [:]))
    }

    /// The click arrives in overlay coordinates while rows publish in the drag named space, so it
    /// takes the same conversion pointer drags and the empty-area menu take.
    func testSecondaryClickConvertsTheClickIntoTheNamedSpaceLikeDragsDo() {
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 14, y: 52, width: 200, height: 400)],
            .customSectionHeader("research"): [CGRect(x: 14, y: 100, width: 200, height: 24)]
        ]

        // Monitor (100, 60) → named (114, 112), inside the header's band.
        XCTAssertEqual(
            sidebarSecondaryClickSectionHighlight(CGPoint(x: 100, y: 60), geometry: geometry)?.sectionID,
            "research"
        )
        // Monitor (100, 112) → named (114, 164), well below it.
        XCTAssertNil(sidebarSecondaryClickSectionHighlight(CGPoint(x: 100, y: 112), geometry: geometry))
    }

    /// `research` is expanded — header plus a member row publishing the terminal — while `reading`
    /// is collapsed, publishing a header and nothing else.
    private static let sectionHighlightGeometry: [SidebarDragGeometryRole: [CGRect]] = [
        .viewport: [CGRect(x: 0, y: 0, width: 200, height: 400)],
        .tasksHeader: [CGRect(x: 0, y: 40, width: 200, height: 24)],
        .customSectionHeader("research"): [CGRect(x: 0, y: 100, width: 200, height: 24)],
        .customSectionTerminal("research"): [CGRect(x: 0, y: 130, width: 200, height: 24)],
        .customSectionHeader("reading"): [CGRect(x: 0, y: 200, width: 200, height: 24)]
    ]

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
