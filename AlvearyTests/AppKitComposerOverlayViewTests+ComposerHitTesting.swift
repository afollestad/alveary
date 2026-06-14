@preconcurrency import AppKit
import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitComposerOverlayViewTests {
    func testNormalComposerHitTestingReachesEditorAfterOverlayIsCleared() throws {
        let layout = AppKitChatComposerPanelView.Layout(
            horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20),
            topContentSpacing: 8,
            actionRowSpacing: 14
        )
        let body = makeComposerBodyConfiguration(text: "Normal composer")
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        panel.configure(AppKitChatComposerPanelConfiguration(
            bodyConfiguration: body,
            actionRowConfiguration: makeOverlayActionRowConfiguration(),
            showsTopDivider: false,
            layout: layout
        ))
        panel.layoutSubtreeIfNeeded()
        let editor = try XCTUnwrap(panel.editorControllerForTesting.view)

        XCTAssertTrue(panel.hitTest(editorCenter(in: panel, editor: editor)).isEditorHit(inside: editor))

        panel.configure(AppKitChatComposerPanelConfiguration(
            bodyConfiguration: body,
            actionRowConfiguration: makeOverlayActionRowConfiguration(),
            interactionOverlayConfiguration: makeOverlayConfiguration(id: "prompt"),
            showsTopDivider: false,
            layout: layout
        ))
        panel.layoutSubtreeIfNeeded()

        XCTAssertFalse(panel.interactionOverlayViewForTesting.isHidden)
        XCTAssertFalse(panel.hitTest(editorCenter(in: panel, editor: editor)).isEditorHit(inside: editor))

        panel.configure(AppKitChatComposerPanelConfiguration(
            bodyConfiguration: body,
            actionRowConfiguration: makeOverlayActionRowConfiguration(),
            showsTopDivider: false,
            layout: layout
        ))
        panel.layoutSubtreeIfNeeded()

        XCTAssertTrue(panel.interactionOverlayViewForTesting.isHidden)
        XCTAssertEqual(panel.interactionOverlayViewForTesting.frame, .zero)
        XCTAssertTrue(panel.hitTest(editorCenter(in: panel, editor: editor)).isEditorHit(inside: editor))
    }
}

@MainActor
private func editorCenter(in panel: AppKitChatComposerPanelView, editor: NSView) -> NSPoint {
    panel.convert(NSPoint(x: editor.bounds.midX, y: editor.bounds.midY), from: editor)
}

private extension Optional where Wrapped == NSView {
    @MainActor
    func isEditorHit(inside editor: NSView) -> Bool {
        guard let self else {
            return false
        }
        return self === editor || self.isDescendant(of: editor)
    }
}
