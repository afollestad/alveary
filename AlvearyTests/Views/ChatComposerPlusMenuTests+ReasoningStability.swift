import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerPlusMenuTests {
    func testReasoningSliderPreviewUpdatesAnchorAndSurvivesEquivalentParentConfigure() throws {
        let options = Self.reasoningStabilityEffortOptions
        let configuration = makeConfiguration(
            mode: .idle,
            effortOptions: options,
            selectedEffort: "ultra",
            defaultEffort: "medium"
        )
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        row.configure(configuration)
        let controller = ComposerReasoningMenuViewController(
            configuration: configuration.reasoning,
            onRequestCloseMainMenu: {},
            onDisplaySelectionChanged: { [weak row] in
                row?.applyReasoningDisplaySelectionOverride($0)
            }
        )
        row.reasoningMenuController = controller
        controller.loadViewIfNeeded()
        let slider = try XCTUnwrap(controller.debugEffortSlider)

        slider.beginTrackingInteraction()
        slider.updateTrackingInteraction(to: 2)
        XCTAssertEqual(row.reasoningButton.accessibilityValue() as? String, "Sonnet, High")

        row.configure(makeConfiguration(
            mode: .idle,
            effortOptions: options,
            selectedEffort: "ultra",
            defaultEffort: "medium"
        ))

        XCTAssertTrue(slider.isTrackingInteraction)
        XCTAssertEqual(row.reasoningButton.accessibilityValue() as? String, "Sonnet, High")
    }

    func testReasoningSliderPreviewClearsForAuthoritativeSelectionChange() throws {
        let options = Self.reasoningStabilityEffortOptions
        let configuration = makeConfiguration(mode: .idle, effortOptions: options)
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        row.configure(configuration)
        let controller = ComposerReasoningMenuViewController(
            configuration: configuration.reasoning,
            onRequestCloseMainMenu: {},
            onDisplaySelectionChanged: { [weak row] in
                row?.applyReasoningDisplaySelectionOverride($0)
            }
        )
        row.reasoningMenuController = controller
        controller.loadViewIfNeeded()
        let slider = try XCTUnwrap(controller.debugEffortSlider)
        slider.beginTrackingInteraction()
        slider.updateTrackingInteraction(to: 2)

        row.configure(makeConfiguration(
            mode: .idle,
            effortOptions: options,
            selectedEffort: "low"
        ))

        XCTAssertFalse(slider.isTrackingInteraction)
        XCTAssertEqual(slider.displayedIndex, 0)
        XCTAssertEqual(row.reasoningButton.accessibilityValue() as? String, "Sonnet, Low")
    }

    func testReasoningSliderPreviewClearsForAuthoritativeEffortOptionsChange() throws {
        var committedEfforts: [String] = []
        let options = Self.reasoningStabilityEffortOptions
        let reorderedOptions = [options[1], options[0], options[2]]
        let configuration = makeConfiguration(mode: .idle, effortOptions: options)
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        row.configure(configuration)
        let controller = ComposerReasoningMenuViewController(
            configuration: configuration.reasoning,
            onRequestCloseMainMenu: {},
            onDisplaySelectionChanged: { [weak row] in row?.applyReasoningDisplaySelectionOverride($0) }
        )
        row.reasoningMenuController = controller
        controller.loadViewIfNeeded()
        let slider = try XCTUnwrap(controller.debugEffortSlider)
        slider.beginTrackingInteraction()
        slider.updateTrackingInteraction(to: 2)

        row.configure(makeConfiguration(
            mode: .idle,
            effortOptions: reorderedOptions,
            onEffortChange: {
                committedEfforts.append($0)
                return true
            }
        ))

        XCTAssertTrue(committedEfforts.isEmpty)
        XCTAssertFalse(slider.isTrackingInteraction)
        XCTAssertEqual(slider.effortTitles, ["Medium", "Low", "High"])
        XCTAssertEqual(slider.displayedIndex, 0)
        XCTAssertNil(row.reasoningDisplaySelectionOverride)
        XCTAssertEqual(row.reasoningButton.accessibilityValue() as? String, "Sonnet, Medium")
    }

    func testReasoningSliderPreviewClearsForAuthoritativeModelChange() throws {
        var committedEfforts: [String] = []
        let options = Self.reasoningStabilityEffortOptions
        let configuration = makeConfiguration(mode: .idle, effortOptions: options)
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        row.configure(configuration)
        let controller = ComposerReasoningMenuViewController(
            configuration: configuration.reasoning,
            onRequestCloseMainMenu: {},
            onDisplaySelectionChanged: { [weak row] in row?.applyReasoningDisplaySelectionOverride($0) }
        )
        row.reasoningMenuController = controller
        controller.loadViewIfNeeded()
        let slider = try XCTUnwrap(controller.debugEffortSlider)
        slider.beginTrackingInteraction()
        slider.updateTrackingInteraction(to: 2)

        row.configure(makeConfiguration(
            mode: .idle,
            modelOptions: [.init(value: "opus", title: "Opus")],
            effortOptions: options,
            onEffortChange: {
                committedEfforts.append($0)
                return true
            }
        ))

        XCTAssertTrue(committedEfforts.isEmpty)
        XCTAssertFalse(slider.isTrackingInteraction)
        XCTAssertEqual(slider.displayedIndex, 1)
        XCTAssertNil(row.reasoningDisplaySelectionOverride)
        XCTAssertEqual(row.reasoningButton.accessibilityValue() as? String, "Opus, Medium")
    }

    func testAcceptedLocalEffortIsReplacedByLaterCanonicalConfiguration() throws {
        let options = Self.reasoningStabilityEffortOptions
        let configuration = makeConfiguration(mode: .idle, effortOptions: options)
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        row.configure(configuration)
        let controller = ComposerReasoningMenuViewController(
            configuration: configuration.reasoning,
            onRequestCloseMainMenu: {},
            onDisplaySelectionChanged: { [weak row] in
                row?.applyReasoningDisplaySelectionOverride($0)
            }
        )
        row.reasoningMenuController = controller
        controller.loadViewIfNeeded()
        let slider = try XCTUnwrap(controller.debugEffortSlider)
        slider.beginTrackingInteraction()
        slider.updateTrackingInteraction(to: 2)
        XCTAssertTrue(slider.endTrackingInteraction(commit: true))
        XCTAssertEqual(row.reasoningButton.accessibilityValue() as? String, "Sonnet, High")

        row.configure(makeConfiguration(
            mode: .idle,
            effortOptions: options,
            selectedEffort: "ultra",
            defaultEffort: "medium"
        ))

        XCTAssertEqual(row.reasoningButton.accessibilityValue() as? String, "Sonnet, Ultra")
        XCTAssertEqual(slider.displayedIndex, 1)
        XCTAssertFalse(slider.debugCanonicalValueIsRepresented)
    }

    func testClosingReasoningMenuCancelsActivePreviewWithoutCommit() throws {
        var committedEfforts: [String] = []
        let options = Self.reasoningStabilityEffortOptions
        let configuration = makeConfiguration(
            mode: .idle,
            effortOptions: options,
            selectedEffort: "ultra",
            defaultEffort: "medium",
            onEffortChange: {
                committedEfforts.append($0)
                return true
            }
        )
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        row.configure(configuration)
        let controller = ComposerReasoningMenuViewController(
            configuration: configuration.reasoning,
            onRequestCloseMainMenu: { [weak row] in row?.closeReasoningMenu() },
            onDisplaySelectionChanged: { [weak row] in
                row?.applyReasoningDisplaySelectionOverride($0)
            }
        )
        let popover = NSPopover()
        row.reasoningMenuController = controller
        row.reasoningPopover = popover
        controller.loadViewIfNeeded()
        let slider = try XCTUnwrap(controller.debugEffortSlider)

        slider.beginTrackingInteraction()
        slider.updateTrackingInteraction(to: 2)
        XCTAssertEqual(row.reasoningButton.accessibilityValue() as? String, "Sonnet, High")

        row.closeReasoningMenu()

        XCTAssertTrue(committedEfforts.isEmpty)
        XCTAssertFalse(slider.isTrackingInteraction)
        XCTAssertEqual(slider.canonicalIndex, 1)
        XCTAssertEqual(slider.displayedIndex, 1)
        XCTAssertEqual(row.reasoningButton.accessibilityValue() as? String, "Sonnet, Ultra")
        XCTAssertFalse(slider.debugCanonicalValueIsRepresented)
        XCTAssertNil(row.reasoningDisplaySelectionOverride)
        XCTAssertNil(row.reasoningMenuController)
        XCTAssertNil(row.reasoningPopover)
        XCTAssertFalse(popover.isShown)
    }

    func testDisablingActionRowCancelsActivePreviewWithoutCommit() throws {
        var committedEfforts: [String] = []
        let options = Self.reasoningStabilityEffortOptions
        let configuration = makeConfiguration(
            mode: .idle,
            effortOptions: options,
            onEffortChange: {
                committedEfforts.append($0)
                return true
            }
        )
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        row.configure(configuration)
        let controller = ComposerReasoningMenuViewController(
            configuration: configuration.reasoning,
            onRequestCloseMainMenu: { [weak row] in row?.closeReasoningMenu() },
            onDisplaySelectionChanged: { [weak row] in
                row?.applyReasoningDisplaySelectionOverride($0)
            }
        )
        let popover = NSPopover()
        row.reasoningMenuController = controller
        row.reasoningPopover = popover
        controller.loadViewIfNeeded()
        let slider = try XCTUnwrap(controller.debugEffortSlider)

        slider.beginTrackingInteraction()
        slider.updateTrackingInteraction(to: 2)
        XCTAssertEqual(row.reasoningButton.accessibilityValue() as? String, "Sonnet, High")

        row.configure(makeConfiguration(
            mode: .idle,
            effortOptions: options,
            areControlsDisabled: true,
            onEffortChange: {
                committedEfforts.append($0)
                return true
            }
        ))

        XCTAssertTrue(committedEfforts.isEmpty)
        XCTAssertFalse(slider.isTrackingInteraction)
        XCTAssertEqual(slider.canonicalIndex, 1)
        XCTAssertEqual(slider.displayedIndex, 1)
        XCTAssertEqual(row.reasoningButton.accessibilityValue() as? String, "Sonnet, Medium")
        XCTAssertNil(row.reasoningDisplaySelectionOverride)
        XCTAssertNil(row.reasoningMenuController)
        XCTAssertNil(row.reasoningPopover)
        XCTAssertFalse(popover.isShown)
    }

    private static var reasoningStabilityEffortOptions: [ChatComposerActionRowView.MenuOption] {
        [
            .init(value: "low", title: "Low"),
            .init(value: "medium", title: "Medium"),
            .init(value: "high", title: "High")
        ]
    }
}
