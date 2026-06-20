@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitComposerOverlayViewTests {
    func testTooltipAnchorLetsHitTestingPassThrough() {
        let anchor = AppKitHoverTooltipAnchorView(frame: NSRect(x: 0, y: 0, width: 12, height: 12))

        XCTAssertNil(anchor.hitTest(NSPoint(x: 6, y: 6)))
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

    func testTooltipAnchorRefreshesAndClosesWhenTextChanges() {
        let anchor = AppKitHoverTooltipAnchorView(frame: NSRect(x: 20, y: 20, width: 12, height: 12))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        let contentView = NSView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 500, height: 200))
        window.contentView = contentView
        contentView.addSubview(anchor)
        anchor.configure(helpText: "First path")
        anchor.showTooltipForTesting()
        XCTAssertTrue(anchor.tooltipIsShownForTesting)

        anchor.configure(helpText: "Second path")
        XCTAssertTrue(anchor.tooltipIsShownForTesting)

        anchor.configure(helpText: "")
        XCTAssertFalse(anchor.tooltipIsShownForTesting)

        anchor.configure(helpText: "Third path")
        anchor.showTooltipForTesting()
        XCTAssertTrue(anchor.tooltipIsShownForTesting)

        anchor.configure(helpText: nil)
        XCTAssertFalse(anchor.tooltipIsShownForTesting)
    }
}
