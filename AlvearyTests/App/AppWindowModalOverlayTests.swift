import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppWindowModalOverlayTests: XCTestCase {
    func testEscapeKeyDismissesOverlayPanel() {
        let panel = AppWindowModalOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        var dismissCount = 0
        panel.onDismiss = { dismissCount += 1 }

        panel.sendEvent(keyEvent(keyCode: 53))

        XCTAssertEqual(dismissCount, 1)
    }

    func testCancelOperationDismissesOverlayPanel() {
        let panel = AppWindowModalOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        var dismissCount = 0
        panel.onDismiss = { dismissCount += 1 }

        panel.cancelOperation(nil)

        XCTAssertEqual(dismissCount, 1)
    }

    func testEscapeKeyDoesNotDismissNonDismissibleOverlayPanel() {
        let panel = AppWindowModalOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.dismissPolicy = .nonDismissible
        var dismissCount = 0
        panel.onDismiss = { dismissCount += 1 }

        panel.sendEvent(keyEvent(keyCode: 53))

        XCTAssertEqual(dismissCount, 0)
    }

    func testCancelOperationDoesNotDismissNonDismissibleOverlayPanel() {
        let panel = AppWindowModalOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.dismissPolicy = .nonDismissible
        var dismissCount = 0
        panel.onDismiss = { dismissCount += 1 }

        panel.cancelOperation(nil)

        XCTAssertEqual(dismissCount, 0)
    }

    func testTrafficLightCutoutDoesNotHitOverlayContent() {
        let contentView = AppWindowModalOverlayContentView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        contentView.trafficLightCutoutFrames = [NSRect(x: 12, y: 260, width: 14, height: 14)]

        XCTAssertNil(contentView.hitTest(NSPoint(x: 18, y: 267)))
        XCTAssertEqual(contentView.hitTest(NSPoint(x: 100, y: 100)), contentView)
    }

    private func keyEvent(keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: keyCode
        ) ?? NSEvent()
    }
}
