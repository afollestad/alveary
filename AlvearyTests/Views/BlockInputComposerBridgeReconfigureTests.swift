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

    func testSkippedViewReconfigureUsesLatestModalOverlayProvider() {
        var usedInitialProvider = false
        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(
            markdown: "Before",
            modalOverlayProvider: { _ in
                usedInitialProvider = true
                return nil
            }
        ))
        let installedConfiguration = controller.blockInputConfiguration(for: makeConfiguration(
            markdown: "Before",
            modalOverlayProvider: { _ in nil }
        ))
        controller.configure(makeConfiguration(
            markdown: "Before",
            modalOverlayProvider: { context in
                BlockInputModalOverlay(
                    container: context.defaultContainer,
                    frame: NSRect(x: 9, y: 10, width: 11, height: 12)
                )
            }
        ))

        let overlay = installedConfiguration.modalOverlayProvider?(
            BlockInputModalOverlayContext(
                editorView: controller.view,
                kind: .link,
                defaultContainer: controller.view,
                defaultFrame: .zero,
                modalSize: NSSize(width: 11, height: 12),
                anchorWindowRect: .zero
            )
        )

        XCTAssertFalse(usedInitialProvider)
        XCTAssertTrue(overlay?.container === controller.view)
        XCTAssertEqual(overlay?.frame, NSRect(x: 9, y: 10, width: 11, height: 12))
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

    func testModalOverlayProviderPresenceChangeDoesNotReconfigureBlockInputView() {
        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(markdown: "Before"))
        let installedConfiguration = controller.blockInputConfiguration(for: makeConfiguration(markdown: "Before"))
        #if DEBUG
        let initialConfigureCount = controller.viewConfigureCountForTesting
        #endif

        controller.configure(makeConfiguration(
            markdown: "Before",
            modalOverlayProvider: { context in
                BlockInputModalOverlay(
                    container: context.defaultContainer,
                    frame: NSRect(x: 13, y: 14, width: 15, height: 16)
                )
            }
        ))

        let overlay = installedConfiguration.modalOverlayProvider?(
            BlockInputModalOverlayContext(
                editorView: controller.view,
                kind: .image,
                defaultContainer: controller.view,
                defaultFrame: .zero,
                modalSize: NSSize(width: 15, height: 16),
                anchorWindowRect: .zero
            )
        )

        #if DEBUG
        XCTAssertEqual(controller.viewConfigureCountForTesting, initialConfigureCount)
        #endif
        XCTAssertEqual(overlay?.frame, NSRect(x: 13, y: 14, width: 15, height: 16))
    }

    func testImagePresentationChangeReconfiguresBlockInputView() {
        let markdown = "![Cat](cat.png)"
        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(markdown: markdown))
        #if DEBUG
        let initialConfigureCount = controller.viewConfigureCountForTesting
        #endif

        controller.configure(makeConfiguration(markdown: markdown, imagePresentation: .textLinksWithPreviewStrip))
        let blockInputConfiguration = controller.blockInputConfiguration(for: makeConfiguration(
            markdown: markdown,
            imagePresentation: .textLinksWithPreviewStrip
        ))

        XCTAssertEqual(blockInputConfiguration.imagePresentation, .textLinksWithPreviewStrip)
        XCTAssertEqual(controller.currentMarkdown(), markdown)
        #if DEBUG
        XCTAssertEqual(controller.viewConfigureCountForTesting, initialConfigureCount + 1)
        #endif
    }

    private func makeConfiguration(
        markdown: String,
        imagePresentation: BlockInputImagePresentation = .inlineBlocks,
        keyboardShortcuts: [BlockInputKeyboardShortcut: BlockInputKeyboardShortcutHandler] = [:],
        completionPopupOverlayProvider: (@MainActor (BlockInputCompletionPopupOverlayContext) -> BlockInputCompletionPopupOverlay?)? = nil,
        modalOverlayProvider: (@MainActor (BlockInputModalOverlayContext) -> BlockInputModalOverlay?)? = nil,
        onDocumentMutation: @escaping (BlockInputDocumentChange, Bool) -> Void = { _, _ in }
    ) -> BlockInputComposerBridgeConfiguration {
        BlockInputComposerBridgeConfiguration(
            markdown: markdown,
            imagePresentation: imagePresentation,
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/alveary-project"),
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] },
            keyboardShortcuts: keyboardShortcuts,
            completionPopupOverlayProvider: completionPopupOverlayProvider,
            modalOverlayProvider: modalOverlayProvider,
            onDocumentMutation: onDocumentMutation
        )
    }
}
