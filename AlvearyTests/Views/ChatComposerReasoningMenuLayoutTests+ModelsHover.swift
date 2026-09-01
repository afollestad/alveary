import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerReasoningMenuLayoutTests {
    func testScrollingModelListUnderStationaryPointerMovesHoverToRowUnderIt() throws {
        let groups = [modelGroup(
            providerID: "claude",
            title: "Claude",
            models: (0 ..< 20).map { ("model-\($0)", "Model \($0)") }
        )]
        let controller = groupedController(groups: groups)
        controller.setModelsExpanded(true)
        let window = mountForModelsSectionLayout(controller)
        defer { window.contentView = nil }
        defer { ComposerReasoningMenuRowView.debugPointerLocationInWindowOverride = nil }
        let list = try XCTUnwrap(controller.debugModelList)
        let scrollView = try XCTUnwrap(list.modelsDescendants(of: NSScrollView.self).first)
        let hoveredRow = try XCTUnwrap(list.focusableRows[reasoningMenuSafe: 2])
        let nextRow = try XCTUnwrap(list.focusableRows[reasoningMenuSafe: 3])

        ComposerReasoningMenuRowView.debugPointerLocationInWindowOverride = hoveredRow.convert(
            NSPoint(x: hoveredRow.bounds.midX, y: hoveredRow.bounds.midY),
            to: nil
        )
        hoveredRow.mouseEntered(with: NSEvent())
        XCTAssertTrue(hoveredRow.debugShowsInteractionBackground)
        XCTAssertFalse(nextRow.debugShowsInteractionBackground)

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: ComposerReasoningMenuMetrics.rowHeight))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        XCTAssertFalse(hoveredRow.debugShowsInteractionBackground)
        XCTAssertTrue(nextRow.debugShowsInteractionBackground)
        XCTAssertEqual(list.focusableRows.filter(\.debugShowsInteractionBackground).count, 1)
    }

    func testKeyboardFocusScrollClearsStrandedHover() throws {
        let groups = [modelGroup(
            providerID: "claude",
            title: "Claude",
            models: (0 ..< 30).map { ("model-\($0)", "Model \($0)") }
        )]
        let controller = groupedController(groups: groups)
        controller.setModelsExpanded(true)
        let window = mountForModelsSectionLayout(controller)
        defer { window.contentView = nil }
        defer { ComposerReasoningMenuRowView.debugPointerLocationInWindowOverride = nil }
        let list = try XCTUnwrap(controller.debugModelList)
        let hoveredRow = try XCTUnwrap(list.focusableRows[reasoningMenuSafe: 1])
        let lastRow = try XCTUnwrap(list.focusableRows.last)

        ComposerReasoningMenuRowView.debugPointerLocationInWindowOverride = hoveredRow.convert(
            NSPoint(x: hoveredRow.bounds.midX, y: hoveredRow.bounds.midY),
            to: nil
        )
        hoveredRow.mouseEntered(with: NSEvent())
        XCTAssertTrue(hoveredRow.debugShowsInteractionBackground)

        XCTAssertTrue(window.makeFirstResponder(lastRow))

        XCTAssertFalse(hoveredRow.debugShowsInteractionBackground)
    }
}
