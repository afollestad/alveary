@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitComposerOverlayInteractionTests: XCTestCase {
    func testNavigationButtonsRouteClickActions() {
        let panel = AppKitComposerOverlayPanelView(frame: NSRect(x: 0, y: 0, width: 360, height: 220))
        var backwardCount = 0
        var forwardCount = 0
        panel.configure(
            AppKitComposerOverlayPanelView.Configuration(
                title: "Question",
                rows: [
                    makeRowConfiguration(id: "one", title: "One")
                ],
                pageText: "2 of 3",
                canNavigateBackward: true,
                canNavigateForward: true,
                primaryTitle: "Continue",
                onNavigateBackward: { backwardCount += 1 },
                onNavigateForward: { forwardCount += 1 },
                onDismiss: {},
                onPrimary: {}
            )
        )
        panel.layoutSubtreeIfNeeded()

        panel.previousButton.performClick(nil)
        panel.nextButton.performClick(nil)

        XCTAssertEqual(backwardCount, 1)
        XCTAssertEqual(forwardCount, 1)
    }

    func testNavigationButtonsAreClickableThroughOverlayHitTesting() throws {
        let overlay = AppKitComposerOverlayView(frame: NSRect(x: 0, y: 0, width: 360, height: 220))
        var backwardCount = 0
        var forwardCount = 0
        overlay.configure(
            AppKitComposerOverlayConfiguration(
                id: "overlay",
                panelConfiguration: AppKitComposerOverlayPanelView.Configuration(
                    title: "Question",
                    rows: [
                        makeRowConfiguration(id: "one", title: "One")
                    ],
                    pageText: "2 of 3",
                    canNavigateBackward: true,
                    canNavigateForward: true,
                    primaryTitle: "Continue",
                    onNavigateBackward: { backwardCount += 1 },
                    onNavigateForward: { forwardCount += 1 },
                    onDismiss: {},
                    onPrimary: {}
                )
            )
        )
        overlay.frame.size.height = overlay.measuredHeight(width: 360)
        overlay.layoutSubtreeIfNeeded()
        let panel = try XCTUnwrap(views(in: overlay, ofType: AppKitComposerOverlayPanelView.self).first)

        let previousPoint = panel.previousButton.convert(
            NSPoint(x: panel.previousButton.bounds.midX, y: panel.previousButton.bounds.midY),
            to: overlay
        )
        let nextPoint = panel.nextButton.convert(
            NSPoint(x: panel.nextButton.bounds.midX, y: panel.nextButton.bounds.midY),
            to: overlay
        )

        let previousHit = try XCTUnwrap(overlay.hitTest(previousPoint) as? NSButton)
        let nextHit = try XCTUnwrap(overlay.hitTest(nextPoint) as? NSButton)
        previousHit.performClick(nil)
        nextHit.performClick(nil)

        XCTAssertTrue(previousHit === panel.previousButton)
        XCTAssertTrue(nextHit === panel.nextButton)
        XCTAssertEqual(backwardCount, 1)
        XCTAssertEqual(forwardCount, 1)
    }

    func testOptionRowTracksHoverState() {
        let row = AppKitComposerOverlayOptionRowView(frame: NSRect(x: 0, y: 0, width: 360, height: 42))
        row.configure(makeRowConfiguration(id: "one", title: "One"))

        row.mouseEntered(with: makeMouseEvent())
        XCTAssertTrue(row.isHoveringForTesting)

        row.mouseExited(with: makeMouseEvent())
        XCTAssertFalse(row.isHoveringForTesting)
    }

    func testFocusedOptionRowSelectsWithReturnKey() {
        let row = AppKitComposerOverlayOptionRowView(frame: NSRect(x: 0, y: 0, width: 360, height: 42))
        var selectionCount = 0
        row.configure(
            AppKitComposerOverlayOptionRowView.Configuration(
                id: "one",
                indexText: "1.",
                title: "One",
                onSelect: { selectionCount += 1 }
            )
        )

        row.keyDown(with: makeKeyEvent(characters: "\r", keyCode: 36))

        XCTAssertEqual(selectionCount, 1)
    }

    func testFocusedOptionRowUsesSubmitSelectionForReturnKey() {
        let row = AppKitComposerOverlayOptionRowView(frame: NSRect(x: 0, y: 0, width: 360, height: 42))
        var selectionCount = 0
        var submitSelectionCount = 0
        row.configure(
            AppKitComposerOverlayOptionRowView.Configuration(
                id: "one",
                indexText: "1.",
                title: "One",
                onSelect: { selectionCount += 1 },
                onSubmitSelection: { submitSelectionCount += 1 }
            )
        )

        row.keyDown(with: makeKeyEvent(characters: " ", keyCode: 49))
        row.keyDown(with: makeKeyEvent(characters: "\r", keyCode: 36))

        XCTAssertEqual(selectionCount, 1)
        XCTAssertEqual(submitSelectionCount, 1)
    }

    func testPanelReturnSelectsConfiguredFocusedRowWhenPrimaryIsDisabled() {
        let panel = AppKitComposerOverlayPanelView(frame: NSRect(x: 0, y: 0, width: 360, height: 180))
        var selectionCount = 0
        var primaryCount = 0
        panel.configure(
            AppKitComposerOverlayPanelView.Configuration(
                title: "Question",
                rows: [
                    AppKitComposerOverlayOptionRowView.Configuration(
                        id: "one",
                        indexText: "1.",
                        title: "One",
                        isFocused: true,
                        onSelect: { selectionCount += 1 }
                    )
                ],
                primaryTitle: "Continue",
                isPrimaryEnabled: false,
                onDismiss: {},
                onPrimary: { primaryCount += 1 }
            )
        )

        XCTAssertTrue(panel.handleKeyDown(makeKeyEvent(characters: "\r", keyCode: 36)))

        XCTAssertEqual(selectionCount, 1)
        XCTAssertEqual(primaryCount, 0)
    }

    func testPanelReturnUsesSubmitSelectionForConfiguredFocusedRow() {
        let panel = AppKitComposerOverlayPanelView(frame: NSRect(x: 0, y: 0, width: 360, height: 180))
        var selectionCount = 0
        var submitSelectionCount = 0
        var primaryCount = 0
        panel.configure(
            AppKitComposerOverlayPanelView.Configuration(
                title: "Question",
                rows: [
                    AppKitComposerOverlayOptionRowView.Configuration(
                        id: "one",
                        indexText: "1.",
                        title: "One",
                        isFocused: true,
                        onSelect: { selectionCount += 1 },
                        onSubmitSelection: { submitSelectionCount += 1 }
                    )
                ],
                primaryTitle: "Continue",
                isPrimaryEnabled: false,
                onDismiss: {},
                onPrimary: { primaryCount += 1 }
            )
        )

        XCTAssertTrue(panel.handleKeyDown(makeKeyEvent(characters: "\r", keyCode: 36)))

        XCTAssertEqual(selectionCount, 0)
        XCTAssertEqual(submitSelectionCount, 1)
        XCTAssertEqual(primaryCount, 0)
    }
}
