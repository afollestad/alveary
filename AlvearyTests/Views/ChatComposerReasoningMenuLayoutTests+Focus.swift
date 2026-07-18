import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerReasoningMenuLayoutTests {
    func testProgrammaticEffortFocusTargetsSliderInsteadOfModelsDisclosure() throws {
        let controller = makeController(configuration: makeReasoningConfiguration(
            effortOptions: reasoningEffortOptions
        ))
        controller.loadViewIfNeeded()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: controller.preferredContentSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = controller.view
        let slider = try XCTUnwrap(controller.debugEffortSlider)
        let models = try XCTUnwrap(controller.debugModelsDisclosure)
        XCTAssertTrue(window.makeFirstResponder(models))

        XCTAssertTrue(controller.focusEffortControl())

        XCTAssertTrue(window.initialFirstResponder === slider)
        XCTAssertTrue(window.firstResponder === slider)
        XCTAssertFalse(window.firstResponder === models)
    }

    func testProgrammaticEffortFocusFallsBackToModelsWhenSliderIsNotInteractive() throws {
        let controller = makeController(configuration: makeReasoningConfiguration(
            effortOptions: [.init(value: "medium", title: "Medium")]
        ))
        controller.loadViewIfNeeded()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: controller.preferredContentSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = controller.view
        let slider = try XCTUnwrap(controller.debugEffortSlider)
        let models = try XCTUnwrap(controller.debugModelsDisclosure)

        XCTAssertFalse(slider.acceptsFirstResponder)
        XCTAssertTrue(controller.focusEffortControl())
        XCTAssertTrue(window.initialFirstResponder === models)
        XCTAssertTrue(window.firstResponder === models)
    }
}
