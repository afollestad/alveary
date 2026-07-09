@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
final class TerminalSessionHostingViewTests: XCTestCase {
    func testClearingPreviousHostDoesNotDetachReparentedTerminalView() {
        let firstHost = TerminalSessionHostingView()
        let secondHost = TerminalSessionHostingView()
        let terminalView = NSView()

        firstHost.setHostedView(terminalView)
        secondHost.setHostedView(terminalView)
        firstHost.clearHostedView()

        XCTAssertTrue(terminalView.superview === secondHost)
        XCTAssertTrue(secondHost.subviews.contains { $0 === terminalView })
    }

    func testHostedTerminalViewUsesViewportInsets() {
        let host = TerminalSessionHostingView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        let terminalView = NSView()

        host.setHostedView(terminalView)
        host.layoutSubtreeIfNeeded()

        let insets = TerminalSessionHostingView.contentInsets
        XCTAssertEqual(terminalView.frame.minX, insets.left, accuracy: 0.001)
        XCTAssertEqual(terminalView.frame.minY, insets.bottom, accuracy: 0.001)
        XCTAssertEqual(terminalView.frame.width, 320 - insets.left - insets.right, accuracy: 0.001)
        XCTAssertEqual(terminalView.frame.height, 180 - insets.top - insets.bottom, accuracy: 0.001)
    }
}
