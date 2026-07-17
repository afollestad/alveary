import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitChatComposerEditorControllerTests {
    func testConfigureResetsBridgeAndSelectionWhenDraftIdentityChanges() throws {
        let controller = AppKitChatComposerEditorController()

        controller.configure(makeConfiguration(text: "First", draftIdentity: "one"))
        let firstBlockID = try XCTUnwrap(controller.bridgeController?.documentStore.document.blocks.first?.id)
        controller.latestSelection = .cursor(.init(blockID: firstBlockID, utf16Offset: 3))
        controller.configure(makeConfiguration(text: "Second", draftIdentity: "two"))

        XCTAssertEqual(controller.bridgeController?.currentMarkdown(), "Second")
        XCTAssertNil(controller.latestSelection)
    }

    func testEditorInteractionUICallbackTracksModalPresentationAndDismissal() throws {
        let controller = AppKitChatComposerEditorController()
        var interactionStates: [Bool] = []
        let recordInteractionState = { [weak controller] in
            let isPresented = controller?.view?.hasPresentedEditorInteractionUI == true
            guard interactionStates.last != isPresented else { return }
            interactionStates.append(isPresented)
        }
        controller.configure(makeConfiguration(
            text: "Link",
            onVoiceInputAvailabilityChange: recordInteractionState
        ))
        let editor = try XCTUnwrap(controller.view)
        controller.bridgeController?.focusEditorAtDocumentEnd()

        XCTAssertTrue(editor.performCommand(.insertLink(BlockInputInsertLinkCommand(presentation: .modal))))
        XCTAssertEqual(interactionStates, [false, true])

        controller.configure(makeConfiguration(
            text: "Link",
            isVoiceInteractionLocked: true,
            onVoiceInputAvailabilityChange: recordInteractionState
        ))

        XCTAssertEqual(interactionStates, [false, true, false])
    }

    func testNilSelectionInsertionContextUsesLastFocusedEditableBlock() throws {
        let controller = AppKitChatComposerEditorController()
        controller.configure(makeConfiguration(text: "Hello\n\nWorld"))
        let blocks = try XCTUnwrap(controller.bridgeController?.documentStore.document.blocks)
        XCTAssertEqual(blocks.count, 2)
        controller.latestSelection = .cursor(.init(blockID: blocks[0].id, utf16Offset: blocks[0].utf16Length))
        controller.latestSelection = nil

        let context = try XCTUnwrap(controller.voiceInsertionContext())

        XCTAssertEqual(context.precedingText, "o")
        XCTAssertNil(context.followingText)
        XCTAssertEqual(context.replacementText(for: "dictated"), " dictated")
    }
}
