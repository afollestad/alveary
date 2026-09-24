import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerReasoningMenuLayoutTests {
    func testInheritRowLeadsModelListWithDivider() throws {
        let controller = inheritController(isInheritSelected: false)
        let modelList = try XCTUnwrap(controller.debugModelList)
        let inheritRow = try XCTUnwrap(modelList.debugInheritRow)

        XCTAssertTrue(modelList.debugArrangedViews.first === inheritRow)
        XCTAssertTrue(modelList.debugArrangedViews.dropFirst().first is AppKitComposerPopoverDividerView)
        XCTAssertEqual(inheritRow.debugSubtitle, "Claude Code · Sonnet · Medium")
        XCTAssertEqual(inheritRow.accessibilityLabel(), "Threads default, Claude Code · Sonnet · Medium")
        XCTAssertNil(inheritRow.debugTrailingIconName)
        XCTAssertEqual(checkedModelRowCount(in: modelList), 1)
    }

    func testSelectedInheritRowOwnsCheckmarkAndFocus() throws {
        let controller = inheritController(isInheritSelected: true)
        let modelList = try XCTUnwrap(controller.debugModelList)
        let inheritRow = try XCTUnwrap(modelList.debugInheritRow)

        XCTAssertEqual(inheritRow.debugTrailingIconName, "checkmark")
        XCTAssertEqual(checkedModelRowCount(in: modelList), 0)
        XCTAssertTrue(modelList.preferredFocusRow === inheritRow)
    }

    func testSelectingInheritMovesCheckmarkBeforeHostRerenders() throws {
        var inheritSelections = 0
        let controller = inheritController(isInheritSelected: false, onInheritSelected: {
            inheritSelections += 1
            return .applied(selection: makeGroupedReasoningConfiguration().selection)
        })
        let modelList = try XCTUnwrap(controller.debugModelList)

        controller.selectInherit()

        XCTAssertEqual(inheritSelections, 1)
        XCTAssertEqual(modelList.debugInheritRow?.debugTrailingIconName, "checkmark")
        XCTAssertEqual(checkedModelRowCount(in: modelList), 0)
    }

    func testRejectedInheritSelectionClosesWithoutMovingCheckmark() throws {
        var closeRequests = 0
        let controller = inheritController(
            isInheritSelected: false,
            onInheritSelected: { .rejected },
            onRequestCloseMainMenu: { closeRequests += 1 }
        )
        let modelList = try XCTUnwrap(controller.debugModelList)

        controller.selectInherit()

        XCTAssertEqual(closeRequests, 1)
        XCTAssertNil(modelList.debugInheritRow?.debugTrailingIconName)
        XCTAssertEqual(checkedModelRowCount(in: modelList), 1)
    }

    func testSelectingModelWhileInheritedClearsInheritCheckmark() throws {
        let controller = inheritController(isInheritSelected: true, onModelChange: { request in
            .applied(selection: makeGroupedReasoningConfiguration(
                selectedHarnessID: request.harnessID,
                selectedModelID: request.modelID
            ).selection)
        })
        let modelList = try XCTUnwrap(controller.debugModelList)

        controller.selectModel(.init(harnessID: "codex", modelID: "gpt-5.5"))

        XCTAssertNil(modelList.debugInheritRow?.debugTrailingIconName)
        XCTAssertEqual(checkedModelRowCount(in: modelList), 1)
    }

    func testCommittingEffortWhileInheritedClearsInheritCheckmark() throws {
        let controller = inheritController(isInheritSelected: true)
        let window = mountForModelsSectionLayout(controller)
        defer { window.contentView = nil }
        let modelList = try XCTUnwrap(controller.debugModelList)
        let slider = try XCTUnwrap(controller.debugEffortSlider)

        slider.keyDown(with: modelRowKeyEvent(keyCode: 124, window: window))

        XCTAssertNil(modelList.debugInheritRow?.debugTrailingIconName)
        XCTAssertEqual(checkedModelRowCount(in: modelList), 1)
    }

    func testInheritRowHeightMatchesMetrics() throws {
        let controller = inheritController(isInheritSelected: false)
        let window = mountForModelsSectionLayout(controller)
        defer { window.contentView = nil }
        let modelList = try XCTUnwrap(controller.debugModelList)
        let lastRow = try XCTUnwrap(modelList.debugArrangedViews.last)

        XCTAssertEqual(
            lastRow.frame.maxY + ComposerReasoningMenuMetrics.modelListBottomInset,
            modelList.debugDocumentHeight
        )
        XCTAssertEqual(
            modelList.debugInheritRow?.frame.height,
            ComposerReasoningMenuMetrics.subtitledRowHeight
        )
    }

    func testInheritRowBuildsLazilyWithModelRows() throws {
        let controller = inheritController(isInheritSelected: true, isModelsExpanded: false)
        let modelList = try XCTUnwrap(controller.debugModelList)

        XCTAssertNil(modelList.debugInheritRow)

        controller.setModelsExpanded(true, animated: false)
        XCTAssertNotNil(modelList.debugInheritRow)
    }

    private func inheritController(
        isInheritSelected: Bool,
        isModelsExpanded: Bool = true,
        onInheritSelected: @escaping () -> ReasoningModelSelectionOutcome = { .rejected },
        onModelChange: @escaping (ReasoningModelSelectionRequest) -> ReasoningModelSelectionOutcome = { _ in .rejected },
        onRequestCloseMainMenu: @escaping () -> Void = {}
    ) -> ComposerReasoningMenuViewController {
        var configuration = makeGroupedReasoningConfiguration(onModelChange: onModelChange)
        configuration.inheritChoice = ReasoningInheritChoice(
            option: .init(
                title: "Threads default",
                detail: "Claude Code · Sonnet · Medium",
                isSelected: isInheritSelected,
                isEnabled: true
            ),
            onSelect: onInheritSelected
        )
        let controller = ComposerReasoningMenuViewController(
            configuration: configuration,
            onRequestCloseMainMenu: onRequestCloseMainMenu,
            reducesMotion: { false }
        )
        controller.loadViewIfNeeded()
        controller.setModelsExpanded(isModelsExpanded)
        return controller
    }

    private func checkedModelRowCount(in modelList: ComposerReasoningModelListView) -> Int {
        modelList.debugArrangedViews
            .compactMap { $0 as? ComposerReasoningMenuRowView }
            .filter { $0 !== modelList.debugInheritRow && $0.debugTrailingIconName == "checkmark" }
            .count
    }
}
