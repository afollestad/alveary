import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
final class AppWindowModalOverlayTests: XCTestCase {
    func testOverlayPanelIsAccessibilityModal() {
        let panel = AppWindowModalOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(panel.isAccessibilityModal())
    }

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

    func testCloseWindowCommandDismissesDismissibleOverlayPanel() {
        let panel = AppWindowModalOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        var dismissCount = 0
        panel.onDismiss = { dismissCount += 1 }

        panel.performClose(nil)

        XCTAssertEqual(dismissCount, 1)
    }

    func testCloseWindowCommandDoesNotDismissNonDismissibleOverlayPanel() {
        let panel = AppWindowModalOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.dismissPolicy = .nonDismissible
        var dismissCount = 0
        panel.onDismiss = { dismissCount += 1 }

        panel.performClose(nil)

        XCTAssertEqual(dismissCount, 0)
    }

    func testNonDismissibleOverlaySwallowsEveryTrafficLightAction() throws {
        let parentWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 500, height: 320),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let panel = AppWindowModalOverlayPanel(
            contentRect: parentWindow.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.parentModalWindow = parentWindow
        panel.dismissPolicy = .nonDismissible
        let actionTarget = TrafficLightActionTarget()

        for buttonType in [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton
        ] {
            let button = try XCTUnwrap(parentWindow.standardWindowButton(buttonType))
            button.target = actionTarget
            button.action = #selector(TrafficLightActionTarget.performAction(_:))

            panel.sendEvent(try mouseEvent(over: button, parentWindow: parentWindow, panel: panel))
        }

        XCTAssertEqual(actionTarget.actionCount, 0)
    }

    func testTrafficLightCutoutDoesNotHitOverlayContent() {
        let contentView = AppWindowModalOverlayContentView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        contentView.trafficLightCutoutFrames = [NSRect(x: 12, y: 260, width: 14, height: 14)]

        XCTAssertNil(contentView.hitTest(NSPoint(x: 18, y: 267)))
        XCTAssertEqual(contentView.hitTest(NSPoint(x: 100, y: 100)), contentView)
    }

    func testChangingModalIdentityReplacesHostingViewState() throws {
        let contentView = AppWindowModalOverlayContentView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let coordinator = AppWindowModalOverlayPresenter.Coordinator()

        coordinator.replaceHostingView(
            with: .init(id: "first", content: AnyView(Text("First"))),
            in: contentView
        )
        let firstHostingView = try XCTUnwrap(contentView.subviews.first)

        coordinator.replaceHostingView(
            with: .init(id: "second", content: AnyView(Text("Second"))),
            in: contentView
        )
        let secondHostingView = try XCTUnwrap(contentView.subviews.first)

        XCTAssertEqual(contentView.subviews.count, 1)
        XCTAssertFalse(firstHostingView === secondHostingView)
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

    private func mouseEvent(
        over button: NSButton,
        parentWindow: NSWindow,
        panel: NSWindow
    ) throws -> NSEvent {
        let buttonFrame = button.convert(button.bounds, to: nil)
        let screenPoint = parentWindow.convertPoint(toScreen: NSPoint(
            x: buttonFrame.midX,
            y: buttonFrame.midY
        ))
        return try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: panel.convertPoint(fromScreen: screenPoint),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
    }
}

private final class TrafficLightActionTarget: NSObject {
    private(set) var actionCount = 0

    @objc func performAction(_ sender: Any?) {
        actionCount += 1
    }
}
