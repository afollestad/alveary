@preconcurrency import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension AppKitComposerOverlayViewTests {
    func testTooltipAnchorLetsHitTestingPassThrough() {
        let anchor = AppKitHoverTooltipAnchorView(frame: NSRect(x: 0, y: 0, width: 12, height: 12))

        XCTAssertNil(anchor.hitTest(NSPoint(x: 6, y: 6)))
    }

    func testTooltipAnchorReportsHoverWithoutInterceptingHitTesting() {
        let anchor = AppKitHoverTooltipAnchorView(frame: NSRect(x: 0, y: 0, width: 12, height: 12))
        var hoverStates: [Bool] = []
        anchor.configure(helpText: "Disabled", onHover: { hoverStates.append($0) })

        anchor.setHoveringForTesting(true)
        anchor.endHoverTracking()

        XCTAssertEqual(hoverStates, [true, false])
    }

    func testTooltipContentPreservesWrappedFittingHeight() {
        let shortController = NSHostingController(rootView: AppHoverTooltipContent(text: "Short help"))
        let wrappedController = NSHostingController(rootView: AppHoverTooltipContent(
            text: "This thread is attached to a scheduled task. Remove or retarget that schedule before continuing."
        ))

        let shortSize = shortController.view.fittingSize
        let wrappedSize = wrappedController.view.fittingSize

        XCTAssertGreaterThan(wrappedSize.height, shortSize.height)
        XCTAssertLessThanOrEqual(wrappedSize.width, 304)
    }

    func testTooltipAnchorWindowDoesNotInterceptMouseEvents() {
        let anchor = AppKitHoverTooltipAnchorView(frame: NSRect(x: 20, y: 20, width: 12, height: 12))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        let contentView = NSView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 500, height: 200))
        window.contentView = contentView
        contentView.addSubview(anchor)
        anchor.configure(helpText: "Pick the direct path.")

        anchor.showTooltipForTesting()

        XCTAssertEqual(anchor.tooltipIgnoresMouseForTesting, true)
        anchor.closeHoverTooltip()
    }

    func testInfoButtonDoesNotRebuildTooltipForUnchangedText() {
        let button = AppKitHoverInfoButton(frame: NSRect(x: 20, y: 20, width: 14, height: 14))
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 500, height: 200),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 500, height: 200))
        window.contentView = contentView
        contentView.addSubview(button)
        button.configure(helpText: "First path")
        button.showTooltipForTesting()
        XCTAssertEqual(button.tooltipContentBuildCountForTesting, 1)
        XCTAssertTrue(button.tooltipIsShownForTesting)

        button.configure(helpText: "First path")
        XCTAssertEqual(button.tooltipContentBuildCountForTesting, 1)
        XCTAssertTrue(button.tooltipIsShownForTesting)

        button.configure(helpText: "Second path")
        XCTAssertEqual(button.tooltipContentBuildCountForTesting, 2)
        XCTAssertTrue(button.tooltipIsShownForTesting)

        button.configure(helpText: "")
        XCTAssertFalse(button.tooltipIsShownForTesting)
    }

    func testTooltipAnchorRefreshesAndClosesWhenTextChanges() {
        let anchor = AppKitHoverTooltipAnchorView(frame: NSRect(x: 20, y: 20, width: 12, height: 12))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        let contentView = NSView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 500, height: 200))
        window.contentView = contentView
        contentView.addSubview(anchor)
        anchor.configure(helpText: "First path")
        anchor.showTooltipForTesting()
        XCTAssertTrue(anchor.tooltipIsShownForTesting)
        XCTAssertEqual(anchor.tooltipContentBuildCountForTesting, 1)

        anchor.configure(helpText: "First path")
        XCTAssertEqual(anchor.tooltipContentBuildCountForTesting, 1)

        anchor.configure(helpText: "Second path")
        XCTAssertTrue(anchor.tooltipIsShownForTesting)
        XCTAssertEqual(anchor.tooltipContentBuildCountForTesting, 2)

        anchor.configure(helpText: "")
        XCTAssertFalse(anchor.tooltipIsShownForTesting)

        anchor.configure(helpText: "Third path")
        anchor.showTooltipForTesting()
        XCTAssertTrue(anchor.tooltipIsShownForTesting)

        anchor.configure(helpText: nil)
        XCTAssertFalse(anchor.tooltipIsShownForTesting)
    }
}
