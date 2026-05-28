import AppKit
import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
final class BlockInputComposerBridgeReconfigureTests: XCTestCase {
    func testMirroredDraftReconfigureDoesNotReconfigureBlockInputView() {
        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(markdown: "Before"))
        let document = BlockInputDocument(markdown: "User edit")
        controller.documentStore.replaceDocument(document)
        #if DEBUG
        let initialConfigureCount = controller.viewConfigureCountForTesting
        #endif

        controller.configure(makeConfiguration(markdown: document.markdown))

        XCTAssertEqual(controller.currentMarkdown(), "User edit")
        #if DEBUG
        XCTAssertEqual(controller.viewConfigureCountForTesting, initialConfigureCount)
        #endif
    }

    func testSkippedViewReconfigureUsesLatestMutationCallback() {
        var usedInitialCallback = false
        var latestMutationEmptyState: Bool?
        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(
            markdown: "Before",
            onDocumentMutation: { _, _ in usedInitialCallback = true }
        ))
        let installedConfiguration = controller.blockInputConfiguration(for: makeConfiguration(markdown: "Before"))
        controller.configure(makeConfiguration(
            markdown: "Before",
            onDocumentMutation: { _, isEffectivelyEmpty in latestMutationEmptyState = isEffectivelyEmpty }
        ))

        controller.documentStore.replaceDocument(BlockInputDocument(markdown: ""))
        installedConfiguration.onDocumentMutation?(.replaceDocument(controller.documentStore.document))

        XCTAssertFalse(usedInitialCallback)
        XCTAssertEqual(latestMutationEmptyState, true)
    }

    func testSkippedViewReconfigureUsesLatestKeyboardShortcutHandler() {
        var usedInitialHandler = false
        var usedLatestHandler = false
        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(
            markdown: "Before",
            keyboardShortcuts: [
                .returnKey: { _ in
                    usedInitialHandler = true
                    return .ignored
                }
            ]
        ))
        let installedConfiguration = controller.blockInputConfiguration(for: makeConfiguration(
            markdown: "Before",
            keyboardShortcuts: [
                .returnKey: { _ in .ignored }
            ]
        ))
        controller.configure(makeConfiguration(
            markdown: "Before",
            keyboardShortcuts: [
                .returnKey: { _ in
                    usedLatestHandler = true
                    return .handled
                }
            ]
        ))

        let result = installedConfiguration.keyboardShortcuts[.returnKey]?(BlockInputKeyboardShortcutContext(
            shortcut: .returnKey,
            selection: nil,
            activeBlock: nil,
            focusSource: .blockText,
            isRepeat: false
        ))

        XCTAssertEqual(result, .handled)
        XCTAssertFalse(usedInitialHandler)
        XCTAssertTrue(usedLatestHandler)
    }

    func testSkippedViewReconfigureUsesLatestOverlayProvider() {
        var usedInitialProvider = false
        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(
            markdown: "Before",
            completionPopupOverlayProvider: { _ in
                usedInitialProvider = true
                return nil
            }
        ))
        let installedConfiguration = controller.blockInputConfiguration(for: makeConfiguration(
            markdown: "Before",
            completionPopupOverlayProvider: { _ in nil }
        ))
        controller.configure(makeConfiguration(
            markdown: "Before",
            completionPopupOverlayProvider: { context in
                BlockInputCompletionPopupOverlay(
                    container: context.defaultContainer,
                    frame: NSRect(x: 5, y: 6, width: 7, height: 8)
                )
            }
        ))

        let overlay = installedConfiguration.completionPopupConfiguration.overlayProvider?(
            BlockInputCompletionPopupOverlayContext(
                editorView: controller.view,
                defaultContainer: controller.view,
                defaultFrame: .zero,
                popupSize: NSSize(width: 7, height: 8)
            )
        )

        XCTAssertFalse(usedInitialProvider)
        XCTAssertTrue(overlay?.container === controller.view)
        XCTAssertEqual(overlay?.frame, NSRect(x: 5, y: 6, width: 7, height: 8))
    }

    func testOverlayProviderPresenceChangeDoesNotReconfigureBlockInputView() {
        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(markdown: "Before"))
        let installedConfiguration = controller.blockInputConfiguration(for: makeConfiguration(markdown: "Before"))
        #if DEBUG
        let initialConfigureCount = controller.viewConfigureCountForTesting
        #endif

        controller.configure(makeConfiguration(
            markdown: "Before",
            completionPopupOverlayProvider: { context in
                BlockInputCompletionPopupOverlay(
                    container: context.defaultContainer,
                    frame: NSRect(x: 1, y: 2, width: 3, height: 4)
                )
            }
        ))

        let overlay = installedConfiguration.completionPopupConfiguration.overlayProvider?(
            BlockInputCompletionPopupOverlayContext(
                editorView: controller.view,
                defaultContainer: controller.view,
                defaultFrame: .zero,
                popupSize: NSSize(width: 3, height: 4)
            )
        )

        #if DEBUG
        XCTAssertEqual(controller.viewConfigureCountForTesting, initialConfigureCount)
        #endif
        XCTAssertEqual(overlay?.frame, NSRect(x: 1, y: 2, width: 3, height: 4))
    }

    private func makeConfiguration(
        markdown: String,
        keyboardShortcuts: [BlockInputKeyboardShortcut: BlockInputKeyboardShortcutHandler] = [:],
        completionPopupOverlayProvider: (@MainActor (BlockInputCompletionPopupOverlayContext) -> BlockInputCompletionPopupOverlay?)? = nil,
        onDocumentMutation: @escaping (BlockInputDocumentChange, Bool) -> Void = { _, _ in }
    ) -> BlockInputComposerBridgeConfiguration {
        BlockInputComposerBridgeConfiguration(
            markdown: markdown,
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/alveary-project"),
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] },
            keyboardShortcuts: keyboardShortcuts,
            completionPopupOverlayProvider: completionPopupOverlayProvider,
            onDocumentMutation: onDocumentMutation
        )
    }
}
