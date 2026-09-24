import AppKit
import XCTest

@testable import Alveary

#if DEBUG
@MainActor
extension ChatComposerActionRowTests {
    func testSettingsFieldPinsChevronTrailingAndTruncatesTitleBeforeEffort() throws {
        let button = makeSettingsFieldButton(title: "Default (Codex · GPT-5.3-Codex-Spark-Extended-Context)", width: 260)

        XCTAssertTrue(button.debugIsModelTruncated)
        XCTAssertEqual(try XCTUnwrap(button.debugContentTrailingGap), 0, accuracy: 1)
        let effortFrame = try XCTUnwrap(button.debugEffortFrame)
        let chevronFrame = try XCTUnwrap(button.debugChevronFrame)
        XCTAssertLessThan(effortFrame.maxX, chevronFrame.minX)
    }

    func testSettingsFieldKeepsEffortBesideShortTitleWhileChevronStaysTrailing() throws {
        let button = makeSettingsFieldButton(title: "Claude · Opus 5.5", width: 320)

        XCTAssertFalse(button.debugIsModelTruncated)
        XCTAssertEqual(try XCTUnwrap(button.debugContentTrailingGap), 0, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(button.debugModelEffortGap), 2, accuracy: 1)
        let effortFrame = try XCTUnwrap(button.debugEffortFrame)
        let chevronFrame = try XCTUnwrap(button.debugChevronFrame)
        XCTAssertGreaterThan(chevronFrame.minX - effortFrame.maxX, 100)
    }

    func testSettingsFieldTitleOverrideDrivesLabelAndAccessibilityValue() {
        let button = makeSettingsFieldButton(title: "Default (Claude · Opus 5.5)", width: 300)

        XCTAssertEqual(button.debugDisplayedModelTitle, "Default (Claude · Opus 5.5)")
        XCTAssertEqual(button.accessibilityValue() as? String, "Default (Claude · Opus 5.5), Max")
    }

    func testSettingsFieldIntrinsicWidthStaysWithinFieldBounds() {
        let short = makeSettingsFieldButton(title: "Sonnet", width: 300)
        let long = makeSettingsFieldButton(title: "Default (Codex · GPT-5.3-Codex-Spark-Extended-Context)", width: 300)

        XCTAssertEqual(short.intrinsicContentSize.width, SettingsScreenLayout.settingsPickerWidth)
        XCTAssertEqual(long.intrinsicContentSize.width, ComposerReasoningButton.Presentation.settingsField.maximumWidth)
        XCTAssertEqual(long.intrinsicContentSize.height, SettingsScreenLayout.settingsControlSurfaceHeight)
    }

    func testReasoningPresenterDirectionChoosesAnchorRelativeEdge() {
        let flippedAnchor = ComposerReasoningButton()
        let unflippedAnchor = NSView()
        let above = ComposerReasoningMenuPresenter(onDisplaySelectionChanged: { _ in })
        let below = ComposerReasoningMenuPresenter(direction: .below, onDisplaySelectionChanged: { _ in })

        XCTAssertTrue(flippedAnchor.isFlipped)
        XCTAssertEqual(above.presentationEdge(for: flippedAnchor), .minY)
        XCTAssertEqual(above.presentationEdge(for: unflippedAnchor), .maxY)
        XCTAssertEqual(below.presentationEdge(for: flippedAnchor), .maxY)
        XCTAssertEqual(below.presentationEdge(for: unflippedAnchor), .minY)
    }

    func testReasoningPresenterPlacementKeepsItsSideUnlessAFewModelRowsCannotFit() {
        let allowance = ComposerReasoningMenuMetrics.popoverScreenAllowance
        func placement(
            _ direction: ComposerReasoningMenuPresenter.Direction,
            anchorY: CGFloat,
            screenHeight: CGFloat = 1_000
        ) -> ComposerReasoningMenuPresenter.Placement {
            ComposerReasoningMenuPresenter.placement(
                preferring: direction,
                anchorOnScreen: NSRect(x: 400, y: anchorY, width: 200, height: 30),
                visibleFrame: NSRect(x: 0, y: 0, width: 1_000, height: screenHeight),
                minimumContentHeight: 200
            )
        }

        XCTAssertEqual(placement(.below, anchorY: 300), .init(direction: .below, maximumContentHeight: 300 - allowance))
        XCTAssertEqual(placement(.below, anchorY: 150), .init(direction: .above, maximumContentHeight: 1_000 - 180 - allowance))
        XCTAssertEqual(placement(.below, anchorY: 200, screenHeight: 400), .init(direction: .below, maximumContentHeight: 200 - allowance))
        XCTAssertEqual(placement(.above, anchorY: 300), .init(direction: .above, maximumContentHeight: 1_000 - 330 - allowance))
    }
}

@MainActor
private func makeSettingsFieldButton(title: String, width: CGFloat) -> ComposerReasoningButton {
    let button = ComposerReasoningButton(presentation: .settingsField)
    button.configure(
        selection: makeReasoningConfiguration(
            effortOptions: [.init(value: "max", title: "Max")],
            selectedEffort: "max"
        ).selection,
        title: title,
        height: SettingsScreenLayout.settingsControlSurfaceHeight,
        isEnabled: true,
        showsProgress: false,
        actionHandler: {}
    )
    button.frame = NSRect(x: 0, y: 0, width: width, height: SettingsScreenLayout.settingsControlSurfaceHeight)
    button.layoutSubtreeIfNeeded()
    return button
}
#endif
