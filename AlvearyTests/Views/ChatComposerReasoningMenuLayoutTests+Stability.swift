import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerReasoningMenuLayoutTests {
    func testReasoningSpeedSubmenuSameValueUpdateKeepsRowsStable() throws {
        let controller = ComposerReasoningSpeedMenuViewController(
            selectedSpeedMode: .fast,
            onSpeedSelected: { _ in },
            onHoverChanged: { _ in },
            onCancel: {}
        )
        controller.loadViewIfNeeded()
        let fastRow = try XCTUnwrap(controller.view.reasoningLayoutStabilityDescendants(of: ComposerReasoningMenuRowView.self).first {
            $0.accessibilityLabel() == "Fast"
        })

        controller.update(selectedSpeedMode: .fast)

        let currentFastRow = try XCTUnwrap(controller.view.reasoningLayoutStabilityDescendants(of: ComposerReasoningMenuRowView.self).first {
            $0.accessibilityLabel() == "Fast"
        })
        XCTAssertTrue(currentFastRow === fastRow)
    }

    func testReasoningModelSubmenuSameValueUpdateKeepsRowsStable() throws {
        let groups = makeReasoningStabilityModelGroups(modelCount: 4)
        let controller = ComposerReasoningModelMenuViewController(
            groups: groups,
            selectedProviderID: "claude",
            selectedModelID: "model-0",
            showsProviderHeaders: true,
            onModelSelected: { _ in },
            onHoverChanged: { _ in },
            onCancel: {}
        )
        controller.loadViewIfNeeded()
        let row = try XCTUnwrap(controller.view.reasoningLayoutStabilityDescendants(of: ComposerReasoningMenuRowView.self).first {
            $0.accessibilityLabel() == "Model 0"
        })

        controller.update(
            groups: groups,
            selectedProviderID: "claude",
            selectedModelID: "model-0",
            showsProviderHeaders: true
        )

        let currentRow = try XCTUnwrap(controller.view.reasoningLayoutStabilityDescendants(of: ComposerReasoningMenuRowView.self).first {
            $0.accessibilityLabel() == "Model 0"
        })
        XCTAssertTrue(currentRow === row)
    }
}

private func makeReasoningStabilityModelGroups(modelCount: Int) -> [ChatComposerActionRowView.ReasoningModelGroup] {
    [
        .init(
            providerID: "claude",
            providerTitle: "Claude Code",
            options: (0..<modelCount).map { index in
                .init(providerID: "claude", value: "model-\(index)", title: "Model \(index)")
            }
        )
    ]
}

private extension NSView {
    func reasoningLayoutStabilityDescendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.reasoningLayoutStabilityDescendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}
