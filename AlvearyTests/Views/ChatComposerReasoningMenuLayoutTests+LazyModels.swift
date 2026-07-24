import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerReasoningMenuLayoutTests {
    func testModelRowsBuildLazilyOnFirstDisclosureExpansion() throws {
        let configuration = makeReasoningConfiguration()
        let controller = ComposerReasoningMenuViewController(
            configuration: configuration,
            onRequestCloseMainMenu: {},
            reducesMotion: { false }
        )
        controller.loadViewIfNeeded()
        let modelList = try XCTUnwrap(controller.debugModelList)

        XCTAssertTrue(modelList.focusableRows.isEmpty)

        // Collapsed configuration updates must not pay the row build either.
        controller.update(configuration: configuration)
        XCTAssertTrue(modelList.focusableRows.isEmpty)

        controller.setModelsExpanded(true, animated: false)
        XCTAssertFalse(modelList.focusableRows.isEmpty)

        // Once built, rows survive collapse and later updates keep them fresh.
        controller.setModelsExpanded(false, animated: false)
        XCTAssertFalse(modelList.focusableRows.isEmpty)
        controller.update(configuration: configuration)
        XCTAssertFalse(modelList.focusableRows.isEmpty)
    }
}
