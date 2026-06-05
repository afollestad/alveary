import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerActionRowTests {
    func testNativeKeymapViewUsesDefaultEnterBehaviorCopy() {
        let view = AppKitChatComposerKeymapView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))

        view.configure(.init(supportsMidTurnSteering: true, defaultEnterBehavior: .steer))
        view.layoutSubtreeIfNeeded()

        let labels = view.keymapDescendants(of: NSTextField.self).map(\.stringValue)
        XCTAssertTrue(labels.contains("Send the message, or steer the current turn while the agent is busy."))
        XCTAssertTrue(labels.contains("Queue for the next turn while the agent is working."))
    }

    func testNativeKeymapViewHidesOptionEnterWhenSteeringUnsupported() {
        let view = AppKitChatComposerKeymapView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))

        view.configure(.init(supportsMidTurnSteering: false, defaultEnterBehavior: .queue))
        view.layoutSubtreeIfNeeded()

        let labels = view.keymapDescendants(of: NSTextField.self).map(\.stringValue)
        XCTAssertTrue(labels.contains("Send the message."))
        XCTAssertFalse(labels.contains("Option + Enter"))
    }

    func testNativeKeymapViewExposesAccessibleCloseAndRows() throws {
        let view = AppKitChatComposerKeymapView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))
        var closeCount = 0

        view.configure(
            .init(supportsMidTurnSteering: true, defaultEnterBehavior: .queue),
            onClose: { closeCount += 1 }
        )
        view.layoutSubtreeIfNeeded()

        let closeButton = try XCTUnwrap(
            view.keymapDescendants(of: ComposerIconButton.self).first { $0.accessibilityLabel() == "Close keyboard shortcuts" }
        )
        XCTAssertTrue(closeButton.accessibilityPerformPress())
        XCTAssertEqual(closeCount, 1)

        let rows = view.keymapDescendants(of: NSView.self)
        let enterRow = try XCTUnwrap(
            rows.first { $0.accessibilityLabel() == "Enter, Send the message, or queue it while the agent is busy." }
        )
        XCTAssertEqual(enterRow.accessibilityRole(), .group)
        XCTAssertTrue(rows.contains { $0.accessibilityLabel() == "Shift + Enter, Insert a newline." })
        XCTAssertTrue(
            rows.contains { $0.accessibilityLabel() == "Option + Enter, Steer the current turn immediately while the agent is working." }
        )
        XCTAssertTrue(
            rows.contains { $0.accessibilityLabel() == "Esc, then Esc, During an active turn, double-tap escape to interrupt (stop) the turn." }
        )
    }

    func testNativeKeymapViewWrapsLongDescriptions() throws {
        let view = AppKitChatComposerKeymapView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))
        view.configure(.init(supportsMidTurnSteering: true, defaultEnterBehavior: .queue))
        view.frame.size = view.preferredModalSize
        view.layoutSubtreeIfNeeded()

        let fields = view.keymapDescendants(of: NSTextField.self).filter {
            $0.lineBreakMode == .byWordWrapping && $0.stringValue != "Insert a newline."
        }
        XCTAssertEqual(fields.count, 3)
        for field in fields {
            XCTAssertEqual(field.lineBreakMode, .byWordWrapping)
            XCTAssertEqual(field.maximumNumberOfLines, 0)
            XCTAssertTrue(field.cell?.wraps == true && field.cell?.isScrollable == false)
            XCTAssertGreaterThanOrEqual(
                field.frame.height + 0.5,
                appKitPromptWrappedTextHeight(for: field, width: field.frame.width)
            )
            let row = try XCTUnwrap(
                view.keymapDescendants(of: NSView.self).first {
                    $0.accessibilityLabel()?.contains(field.stringValue) == true
                }
            )
            XCTAssertTrue(view.bounds.insetBy(dx: 0, dy: -0.5).contains(row.convert(row.bounds, to: view)))
        }
    }
}

private extension NSView {
    func keymapDescendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.keymapDescendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}
