import XCTest

@testable import Alveary

@MainActor
extension ChatComposerReasoningMenuLayoutTests {
    func testDisclosureCaretSizeAndOpticalTextSpacingMatchCompactReasoningButton() throws {
        let compactButton = ComposerReasoningButton()
        compactButton.configure(
            selection: makeReasoningConfiguration(
                effortOptions: [.init(value: "medium", title: "Medium")],
                selectedEffort: "medium"
            ).selection,
            height: ChatComposerActionRowView.defaultSettingsControlHeight,
            isEnabled: true,
            showsProgress: false,
            actionHandler: {}
        )
        compactButton.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: compactButton.intrinsicContentSize.width,
                height: ChatComposerActionRowView.defaultSettingsControlHeight
            )
        )
        compactButton.layoutSubtreeIfNeeded()

        let disclosure = ComposerReasoningModelsDisclosureControl(reducesMotion: { true })
        disclosure.frame = NSRect(origin: .zero, size: disclosure.intrinsicContentSize)
        disclosure.configure(isExpanded: false, isEnabled: true, animated: false, onExpansionChange: { _ in })
        disclosure.layoutSubtreeIfNeeded()
        XCTAssertEqual(disclosure.debugChevronFrameCenterRotationDegrees, 0, accuracy: 0.001)

        let compactChevronFrame = try XCTUnwrap(compactButton.debugChevronFrame)
        let compactChevronGap = try XCTUnwrap(compactButton.debugEffortChevronGap)
        XCTAssertEqual(
            max(disclosure.debugChevronFrame.width, disclosure.debugChevronFrame.height),
            max(compactChevronFrame.width, compactChevronFrame.height),
            accuracy: 0.001
        )
        XCTAssertEqual(
            disclosure.debugTitleChevronVisualGap,
            compactChevronGap,
            accuracy: 0.001
        )
        XCTAssertEqual(disclosure.debugTitleChevronVisualGap, ComposerReasoningButton.caretTextSpacing, accuracy: 0.001)

        disclosure.setExpanded(true, animated: false)
        disclosure.layoutSubtreeIfNeeded()

        XCTAssertEqual(disclosure.debugChevronFrameCenterRotationDegrees, 90, accuracy: 0.001)
        XCTAssertEqual(
            disclosure.debugTitleChevronVisualGap,
            compactChevronGap,
            accuracy: 0.001
        )
        XCTAssertEqual(
            disclosure.debugChevronRotationSlotMaxX + ComposerReasoningMenuMetrics.titleTrailing,
            disclosure.bounds.maxX,
            accuracy: 0.001
        )
    }

    func testMouseEffortTrackingReplacesControlsWithSubtleDirectionLabels() throws {
        let controller = makeController(configuration: makeReasoningConfiguration(
            effortOptions: reasoningEffortOptions,
            supportsSpeedMode: true
        ))
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        let slider = try XCTUnwrap(controller.debugEffortSlider)
        let models = try XCTUnwrap(controller.debugModelsDisclosure)
        let fast = try XCTUnwrap(controller.debugFastToggle)
        let faster = try XCTUnwrap(controller.debugFasterLabel)
        let smarter = try XCTUnwrap(controller.debugSmarterLabel)

        slider.beginTrackingInteraction(at: .zero)
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertFalse(controller.debugShowsEffortDragDirections)
        XCTAssertFalse(models.isHidden)
        XCTAssertFalse(fast.isHidden)

        slider.updateTrackingInteraction(
            to: slider.displayedIndex,
            trackingPoint: NSPoint(x: ComposerReasoningEffortSliderMetrics.dragDirectionRevealDistance, y: 0)
        )
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertTrue(controller.debugShowsEffortDragDirections)
        XCTAssertTrue(models.isHidden)
        XCTAssertTrue(fast.isHidden)
        XCTAssertFalse(faster.isHidden)
        XCTAssertFalse(smarter.isHidden)
        XCTAssertEqual(faster.stringValue, "Faster")
        XCTAssertEqual(smarter.stringValue, "Smarter")
        XCTAssertEqual(faster.font, models.debugTitleFont)
        XCTAssertEqual(smarter.font, models.debugTitleFont)
        XCTAssertEqual(faster.textColor, .secondaryLabelColor)
        XCTAssertFalse(faster.isAccessibilityElement())
        XCTAssertFalse(smarter.isAccessibilityElement())
        XCTAssertEqual(faster.frame.minX, slider.frame.minX, accuracy: 0.001)
        XCTAssertEqual(smarter.frame.maxX, slider.frame.maxX, accuracy: 0.001)
        XCTAssertTrue(slider.nextKeyView === slider)

        XCTAssertFalse(slider.endTrackingInteraction(commit: true))
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertFalse(controller.debugShowsEffortDragDirections)
        XCTAssertFalse(models.isHidden)
        XCTAssertFalse(fast.isHidden)
        XCTAssertTrue(faster.isHidden)
        XCTAssertTrue(smarter.isHidden)
        XCTAssertTrue(slider.nextKeyView === models)
    }

    func testEffortDragDirectionLabelsRestoreUnsupportedFastStateOnCancel() throws {
        let controller = makeController(configuration: makeReasoningConfiguration(
            effortOptions: reasoningEffortOptions,
            supportsSpeedMode: false
        ))
        controller.loadViewIfNeeded()
        let slider = try XCTUnwrap(controller.debugEffortSlider)
        let models = try XCTUnwrap(controller.debugModelsDisclosure)
        let fast = try XCTUnwrap(controller.debugFastToggle)

        slider.beginTrackingInteraction(at: .zero)
        slider.updateTrackingInteraction(
            to: slider.displayedIndex,
            trackingPoint: NSPoint(x: ComposerReasoningEffortSliderMetrics.dragDirectionRevealDistance, y: 0)
        )
        XCTAssertTrue(controller.debugShowsEffortDragDirections)
        controller.cancelEffortPreview()

        XCTAssertFalse(controller.debugShowsEffortDragDirections)
        XCTAssertFalse(models.isHidden)
        XCTAssertTrue(fast.isHidden)
        XCTAssertTrue(slider.nextKeyView === models)
    }

    func testAuthoritativeEffortUpdateRestoresControlsDuringMouseTracking() throws {
        let controller = makeController(configuration: makeReasoningConfiguration(
            effortOptions: reasoningEffortOptions,
            selectedEffort: "medium",
            supportsSpeedMode: true
        ))
        controller.loadViewIfNeeded()
        let slider = try XCTUnwrap(controller.debugEffortSlider)

        slider.beginTrackingInteraction(at: .zero)
        slider.updateTrackingInteraction(
            to: 2,
            trackingPoint: NSPoint(x: ComposerReasoningEffortSliderMetrics.dragDirectionRevealDistance, y: 0)
        )
        XCTAssertTrue(controller.debugShowsEffortDragDirections)

        controller.update(configuration: makeReasoningConfiguration(
            effortOptions: reasoningEffortOptions,
            selectedEffort: "high",
            supportsSpeedMode: true
        ))

        XCTAssertFalse(controller.debugShowsEffortDragDirections)
        XCTAssertFalse(slider.isTrackingInteraction)
        XCTAssertFalse(try XCTUnwrap(controller.debugModelsDisclosure).isHidden)
        XCTAssertFalse(try XCTUnwrap(controller.debugFastToggle).isHidden)
    }

    func testDiscreteEffortStepDoesNotShowDragDirectionLabels() throws {
        let controller = makeController(configuration: makeReasoningConfiguration(
            effortOptions: reasoningEffortOptions,
            supportsSpeedMode: true
        ))
        controller.loadViewIfNeeded()
        let slider = try XCTUnwrap(controller.debugEffortSlider)

        XCTAssertTrue(slider.performDiscreteStep(by: 1))

        XCTAssertFalse(controller.debugShowsEffortDragDirections)
        XCTAssertFalse(try XCTUnwrap(controller.debugModelsDisclosure).isHidden)
        XCTAssertFalse(try XCTUnwrap(controller.debugFastToggle).isHidden)
    }
}
