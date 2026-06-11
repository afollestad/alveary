import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerPlusMenuTests {
    func testReasoningMenuUnchangedParentConfigureKeepsHoveredEffortRow() throws {
        let configuration = makeConfiguration(mode: .idle, effortOptions: Self.reasoningStabilityEffortOptions)
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        row.configure(configuration)
        let controller = ComposerReasoningMenuViewController(
            configuration: configuration.reasoning,
            onRequestCloseMainMenu: {}
        )
        row.reasoningMenuController = controller
        controller.loadViewIfNeeded()

        let highRow = try XCTUnwrap(controller.row(label: "High"))
        highRow.mouseEntered(with: mouseEvent(type: .mouseMoved))
        #if DEBUG
        XCTAssertTrue(highRow.debugShowsInteractionBackground)
        #endif

        row.configure(makeConfiguration(mode: .idle, effortOptions: Self.reasoningStabilityEffortOptions))

        let currentHighRow = try XCTUnwrap(controller.row(label: "High"))
        XCTAssertTrue(currentHighRow === highRow)
        #if DEBUG
        XCTAssertTrue(currentHighRow.debugShowsInteractionBackground)
        #endif
    }

    func testReasoningMenuUnchangedParentConfigureKeepsPressedEffortRow() throws {
        let configuration = makeConfiguration(mode: .idle, effortOptions: Self.reasoningStabilityEffortOptions)
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        row.configure(configuration)
        let controller = ComposerReasoningMenuViewController(
            configuration: configuration.reasoning,
            onRequestCloseMainMenu: {}
        )
        row.reasoningMenuController = controller
        controller.loadViewIfNeeded()

        let highRow = try XCTUnwrap(controller.row(label: "High"))
        highRow.mouseDown(with: mouseEvent(type: .leftMouseDown))
        #if DEBUG
        XCTAssertTrue(highRow.debugShowsInteractionBackground)
        #endif

        row.configure(makeConfiguration(mode: .idle, effortOptions: Self.reasoningStabilityEffortOptions))

        let currentHighRow = try XCTUnwrap(controller.row(label: "High"))
        XCTAssertTrue(currentHighRow === highRow)
        #if DEBUG
        XCTAssertTrue(currentHighRow.debugShowsInteractionBackground)
        #endif
    }

    private static var reasoningStabilityEffortOptions: [ChatComposerActionRowView.MenuOption] {
        [
            .init(value: "low", title: "Low"),
            .init(value: "medium", title: "Medium"),
            .init(value: "high", title: "High")
        ]
    }
}

@MainActor
private extension ComposerReasoningMenuViewController {
    func row(label: String) -> ComposerReasoningMenuRowView? {
        view.reasoningStabilityDescendants(of: ComposerReasoningMenuRowView.self).first {
            $0.accessibilityLabel() == label
        }
    }
}

private func mouseEvent(type: NSEvent.EventType) -> NSEvent {
    NSEvent.mouseEvent(
        with: type,
        location: NSPoint(x: 8, y: 8),
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 0
    ) ?? NSEvent()
}

private extension NSView {
    func reasoningStabilityDescendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.reasoningStabilityDescendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}
