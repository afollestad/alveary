import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerReasoningMenuLayoutTests {
    func testReasoningModelSubmenuHeaderlessTopInset() throws {
        let groups = makeHeaderlessModelSubmenuGroups()
        let controller = ComposerReasoningModelMenuViewController(
            groups: groups,
            selectedProviderID: "claude",
            selectedModelID: "model-0",
            showsProviderHeaders: false,
            onModelSelected: { _ in },
            onHoverChanged: { _ in },
            onCancel: {}
        )
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        let rows = controller.view.modelSubmenuDescendants(of: ComposerReasoningMenuRowView.self)
        let firstRow = try XCTUnwrap(rows.first { $0.accessibilityLabel() == "Model 0" })
        let expectedHeight = ComposerReasoningMenuMetrics.headerlessModelMenuTopInset +
            ComposerReasoningMenuMetrics.verticalInset +
            ComposerReasoningMenuMetrics.rowHeight * CGFloat(rows.count)

        XCTAssertTrue(controller.view.modelSubmenuDescendants(of: ComposerReasoningHeaderView.self).isEmpty)
        XCTAssertEqual(firstRow.frame.minY, ComposerReasoningMenuMetrics.headerlessModelMenuTopInset, accuracy: 1)
        XCTAssertEqual(
            ComposerReasoningMenuMetrics.modelDocumentHeight(groups: groups, showsProviderHeaders: false),
            expectedHeight,
            accuracy: 1
        )
    }

    func testReasoningModelSubmenuContentFrameCompensatesForPopoverHostTopInset() throws {
        let controller = makeGroupedReasoningModelMenu()
        controller.loadViewIfNeeded()
        let contentSize = controller.preferredContentSize
        let host = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: contentSize.width,
            height: contentSize.height + ComposerReasoningMenuMetrics.verticalInset
        ))
        host.addSubview(controller.view)

        controller.alignContentViewToPopoverHost()

        let scrollView = try XCTUnwrap(controller.view.modelSubmenuDescendants(of: NSScrollView.self).first)
        let header = try XCTUnwrap(controller.view.modelSubmenuDescendants(of: ComposerReasoningHeaderView.self).first)
        XCTAssertEqual(controller.view.frame.origin.y, 0, accuracy: 1)
        XCTAssertEqual(controller.view.frame.maxY, contentSize.height, accuracy: 1)
        XCTAssertEqual(scrollView.frame, controller.view.bounds)
        XCTAssertEqual(header.frame.minY, ComposerReasoningMenuMetrics.verticalInset, accuracy: 1)
    }
}

@MainActor
private func makeHeaderlessModelSubmenuGroups() -> [ChatComposerActionRowView.ReasoningModelGroup] {
    [
        .init(
            providerID: "claude",
            providerTitle: nil,
            options: [
                .init(providerID: "claude", value: "model-0", title: "Model 0"),
                .init(providerID: "claude", value: "model-1", title: "Model 1")
            ]
        )
    ]
}

private extension NSView {
    func modelSubmenuDescendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.modelSubmenuDescendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}
