import AppKit
import BlockInputKit
import XCTest

@testable import Alveary

/// Guards `editorBaseHeight` against the height the editor actually rests at.
///
/// It seeds `measuredEditorHeight` before BlockInputKit's first measurement lands, so a stale value
/// lays the composer out at the wrong height on the first frame a draft is mounted.
@MainActor
extension AppKitChatComposerEditorControllerTests {
    func testEmptyComposerRestsAtTheSeededEditorHeight() {
        let controller = BlockInputComposerBridgeController(configuration: BlockInputComposerBridgeConfiguration(
            markdown: "",
            editorHorizontalInset: AppKitChatComposerEditorController.editorHorizontalPadding,
            editorVerticalInset: AppKitChatComposerEditorController.editorVerticalPadding,
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/alveary-project"),
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] }
        ))
        controller.view.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        controller.view.layoutSubtreeIfNeeded()

        // Line spacing does not move this: TextKit spaces the gaps between lines, and the
        // visible-line minimum is built from a one-line reference row.
        XCTAssertEqual(
            ceil(controller.view.preferredHeight(forWidth: 600)),
            AppKitChatComposerEditorController.editorBaseHeight,
            accuracy: 0.5
        )
    }

    func testRestingComposerHeightNeedsNoSeedInvalidation() {
        let controller = AppKitChatComposerEditorController()
        var invalidationAnimationFlags: [Bool] = []
        controller.onPreferredSizeInvalidated = { invalidationAnimationFlags.append($0) }

        controller.configure(makeConfiguration(text: ""))
        invalidationAnimationFlags.removeAll()
        _ = controller.measuredHeight(width: 400)

        // The seed already equals the resting height, so the host is not asked to relayout for a
        // correction of zero.
        XCTAssertEqual(invalidationAnimationFlags, [])
        XCTAssertEqual(
            controller.measuredEditorHeight,
            AppKitChatComposerEditorController.editorBaseHeight,
            accuracy: 0.5
        )
    }
}
