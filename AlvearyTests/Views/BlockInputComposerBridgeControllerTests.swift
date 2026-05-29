import AppKit
import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
final class BlockInputComposerBridgeControllerTests: XCTestCase {
    func testLocationUsesWorktreeBeforeProjectPath() {
        let location = BlockInputComposerLocation(
            projectPath: "/tmp/alveary-project",
            worktreePath: "/tmp/alveary-worktree"
        )

        XCTAssertEqual(location.effectiveProjectDirectory, CanonicalPath.normalize("/tmp/alveary-worktree"))
        XCTAssertEqual(location.fileBaseURL?.path, CanonicalPath.normalize("/tmp/alveary-worktree"))
        XCTAssertEqual(location.imageBaseURL?.path, CanonicalPath.normalize("/tmp/alveary-worktree"))
    }

    func testBridgeConfiguresBlockInputComposerDefaults() {
        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(markdown: "Hello"))
        let blockInputConfiguration = controller.blockInputConfiguration(for: makeConfiguration(markdown: "Hello"))

        XCTAssertFalse(blockInputConfiguration.allowsBlockReordering)
        XCTAssertTrue(blockInputConfiguration.rawSlashCommandChips)
        XCTAssertEqual(blockInputConfiguration.completionReturnBehavior, .passthroughExactMatch)
        XCTAssertEqual(blockInputConfiguration.slashCommandAvailability, .documentStart)
        XCTAssertNotNil(blockInputConfiguration.inlineHintProvider)
        XCTAssertEqual(blockInputConfiguration.completionPopupConfiguration.placement, .overlay)
        let popupStyle = blockInputConfiguration.completionPopupConfiguration.style
        XCTAssertEqual(popupStyle.backgroundColor, BlockInputComposerStyle.completionPopupBackgroundColor)
        XCTAssertEqual(popupStyle.borderColor, BlockInputComposerStyle.completionPopupBorderColor)
        XCTAssertEqual(popupStyle.highlightedRowBackgroundColor, BlockInputComposerStyle.completionPopupHighlightColor)
        XCTAssertEqual(popupStyle.cornerRadius, BlockInputComposerStyle.completionPopupCornerRadius)
        XCTAssertEqual(popupStyle.borderWidth, BlockInputComposerStyle.completionPopupBorderWidth)
        XCTAssertEqual(blockInputConfiguration.heightSizing?.defaultVisibleLineCount, 3)
        XCTAssertEqual(blockInputConfiguration.heightSizing?.maximumVisibleLineCount, 9)
        XCTAssertEqual(blockInputConfiguration.heightSizing?.animation, .default)
        XCTAssertNil(blockInputConfiguration.heightSizing?.onPreferredHeightChange)
        XCTAssertNotNil(blockInputConfiguration.heightSizing?.onPreferredHeightTransition)
        XCTAssertEqual(blockInputConfiguration.selectAllBehavior, .document)
        XCTAssertEqual(blockInputConfiguration.editorHorizontalInset, BlockInputConfiguration.defaultEditorHorizontalInset)
        XCTAssertEqual(blockInputConfiguration.editorVerticalInset, BlockInputConfiguration.defaultEditorVerticalInset)
        XCTAssertEqual(BlockInputComposerBridgeController.blockVerticalInsetMultiplier, 0.7)
        XCTAssertEqual(blockInputConfiguration.blockVerticalInsetMultiplier, BlockInputComposerBridgeController.blockVerticalInsetMultiplier)
        XCTAssertEqual(blockInputConfiguration.fileBaseURL?.path, CanonicalPath.normalize("/tmp/alveary-project"))
        XCTAssertEqual(blockInputConfiguration.imageBaseURL?.path, CanonicalPath.normalize("/tmp/alveary-project"))
    }

    func testBridgeAppliesHostEditorInsets() {
        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(markdown: "Hello"))
        let blockInputConfiguration = controller.blockInputConfiguration(
            for: BlockInputComposerBridgeConfiguration(
                markdown: "Hello",
                editorHorizontalInset: 10,
                editorVerticalInset: 12,
                location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/alveary-project"),
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] }
            )
        )

        XCTAssertEqual(blockInputConfiguration.editorHorizontalInset, 10)
        XCTAssertEqual(blockInputConfiguration.editorVerticalInset, 12)
        XCTAssertEqual(blockInputConfiguration.blockVerticalInsetMultiplier, BlockInputComposerBridgeController.blockVerticalInsetMultiplier)
    }

    func testBridgeForwardsPreferredHeightTransitionCallback() {
        var reportedTransition: BlockInputEditorHeightTransition?
        let configuration = BlockInputComposerBridgeConfiguration(
            markdown: "Hello",
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/alveary-project"),
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] },
            onPreferredHeightTransition: { reportedTransition = $0 }
        )
        let controller = BlockInputComposerBridgeController(configuration: configuration)
        let blockInputConfiguration = controller.blockInputConfiguration(for: configuration)
        let transition = BlockInputEditorHeightTransition(
            previousHeight: 20,
            targetHeight: 40,
            animation: .default,
            isInitial: false
        )

        blockInputConfiguration.heightSizing?.onPreferredHeightTransition?(transition)

        XCTAssertEqual(reportedTransition, transition)
    }

    func testBridgeForwardsOverlayCompletionPopupProvider() {
        let configuration = BlockInputComposerBridgeConfiguration(
            markdown: "Hello",
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/alveary-project"),
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] },
            completionPopupOverlayProvider: { context in
                BlockInputCompletionPopupOverlay(
                    container: context.editorView,
                    frame: NSRect(x: 1, y: 2, width: 3, height: 4)
                )
            }
        )
        let controller = BlockInputComposerBridgeController(configuration: configuration)
        let blockInputConfiguration = controller.blockInputConfiguration(for: configuration)

        let overlay = blockInputConfiguration.completionPopupConfiguration.overlayProvider?(
            BlockInputCompletionPopupOverlayContext(
                editorView: controller.view,
                defaultContainer: controller.view,
                defaultFrame: .zero,
                popupSize: NSSize(width: 3, height: 4)
            )
        )

        XCTAssertTrue(overlay?.container === controller.view)
        XCTAssertEqual(overlay?.frame, NSRect(x: 1, y: 2, width: 3, height: 4))
    }

    func testBridgeForwardsModalOverlayProvider() {
        let configuration = BlockInputComposerBridgeConfiguration(
            markdown: "Hello",
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/alveary-project"),
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] },
            modalOverlayProvider: { context in
                BlockInputModalOverlay(
                    container: context.editorView,
                    frame: NSRect(x: 5, y: 6, width: 7, height: 8)
                )
            }
        )
        let controller = BlockInputComposerBridgeController(configuration: configuration)
        let blockInputConfiguration = controller.blockInputConfiguration(for: configuration)

        let overlay = blockInputConfiguration.modalOverlayProvider?(
            BlockInputModalOverlayContext(
                editorView: controller.view,
                kind: .image,
                defaultContainer: controller.view,
                defaultFrame: .zero,
                modalSize: NSSize(width: 7, height: 8),
                anchorWindowRect: .zero
            )
        )

        XCTAssertTrue(overlay?.container === controller.view)
        XCTAssertEqual(overlay?.frame, NSRect(x: 5, y: 6, width: 7, height: 8))
    }

    func testBridgeForwardsHostKeyboardShortcuts() {
        let shortcuts: [BlockInputKeyboardShortcut: BlockInputKeyboardShortcutHandler] = [
            .returnKey: { _ in .handled },
            .shiftReturn: { _ in .ignored },
            .optionReturn: { _ in .handled },
            BlockInputKeyboardShortcut(key: .escape): { _ in .handled }
        ]

        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(markdown: "Hello"))
        let blockInputConfiguration = controller.blockInputConfiguration(
            for: makeConfiguration(markdown: "Hello", keyboardShortcuts: shortcuts)
        )

        XCTAssertEqual(Set(blockInputConfiguration.keyboardShortcuts.keys), Set(shortcuts.keys))
    }

    func testDocumentMutationReportsEffectiveEmptyWithoutMarkdownSerialization() {
        var reportedIsEmpty: Bool?
        let configuration = makeConfiguration(markdown: "Hello") { reportedIsEmpty = $1 }
        let controller = BlockInputComposerBridgeController(configuration: configuration)
        let blockInputConfiguration = controller.blockInputConfiguration(for: configuration)

        controller.documentStore.replaceDocument(BlockInputDocument(markdown: ""))
        blockInputConfiguration.onDocumentMutation?(.replaceDocument(controller.documentStore.document))

        XCTAssertEqual(reportedIsEmpty, true)
    }

    func testBridgeReplacesExternalMarkdownAndResetsUndo() {
        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(markdown: "Before"))
        let initialUndoController = controller.undoController

        controller.configure(makeConfiguration(markdown: "After", markdownRevision: 1))

        XCTAssertEqual(controller.currentMarkdown(), "After")
        XCTAssertFalse(controller.undoController === initialUndoController)
    }

    func testDocumentChangeKeepsUserEditWithoutResettingUndo() {
        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(markdown: "Before"))
        let initialUndoController = controller.undoController
        let document = BlockInputDocument(markdown: "User edit")
        let blockInputConfiguration = controller.blockInputConfiguration(for: makeConfiguration(markdown: "Before"))

        controller.documentStore.replaceDocument(document)
        blockInputConfiguration.onDocumentChange?(document)
        controller.configure(makeConfiguration(markdown: "User edit"))

        XCTAssertEqual(controller.currentMarkdown(), "User edit")
        XCTAssertTrue(controller.undoController === initialUndoController)
    }

    func testCoalescedPublishDoesNotResetUndoForLiveDocument() {
        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(markdown: "Before"))
        let initialUndoController = controller.undoController
        let blockInputConfiguration = controller.blockInputConfiguration(for: makeConfiguration(markdown: "Before"))
        let document = BlockInputDocument(markdown: "User edit")

        controller.documentStore.replaceDocument(document)
        blockInputConfiguration.onDocumentChange?(document)
        controller.configure(makeConfiguration(markdown: "User edit"))

        XCTAssertEqual(controller.currentMarkdown(), "User edit")
        XCTAssertTrue(controller.undoController === initialUndoController)
    }

    func testStaleExternalMarkdownDoesNotReplaceUserEditBeforeCoalescedPublish() {
        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(markdown: "Before"))
        let initialUndoController = controller.undoController
        let staleConfiguration = makeConfiguration(markdown: "Before")
        let blockInputConfiguration = controller.blockInputConfiguration(for: staleConfiguration)
        let document = BlockInputDocument(markdown: "User edit")

        controller.documentStore.replaceDocument(document)
        blockInputConfiguration.onDocumentChange?(document)
        controller.configure(staleConfiguration)

        XCTAssertEqual(controller.currentMarkdown(), "User edit")
        XCTAssertTrue(controller.undoController === initialUndoController)
    }

    func testExternalRevisionCanReplaceUserEditWithLastConfiguredMarkdown() {
        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(markdown: ""))
        let initialUndoController = controller.undoController
        let blockInputConfiguration = controller.blockInputConfiguration(for: makeConfiguration(markdown: ""))
        let document = BlockInputDocument(markdown: "User edit")

        controller.documentStore.replaceDocument(document)
        blockInputConfiguration.onDocumentChange?(document)
        controller.configure(makeConfiguration(markdown: "", markdownRevision: 1))

        XCTAssertEqual(controller.currentMarkdown(), "")
        XCTAssertFalse(controller.undoController === initialUndoController)
    }

    func testExternalRevisionCanClearLiveDocumentBeforeCoalescedPublish() {
        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(markdown: ""))
        let initialUndoController = controller.undoController

        controller.documentStore.replaceDocument(BlockInputDocument(markdown: "User edit"))
        controller.configure(makeConfiguration(markdown: "", markdownRevision: 1))

        XCTAssertEqual(controller.currentMarkdown(), "")
        XCTAssertFalse(controller.undoController === initialUndoController)
    }

    func testSameLocationReconfigureKeepsCompletionProviderIdentity() {
        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(markdown: "Before"))
        let initialProvider = controller.completionProvider

        controller.configure(makeConfiguration(markdown: "After"))

        XCTAssertTrue(controller.completionProvider === initialProvider)
    }

    func testSameLocationReconfigureUsesLatestCompletionLoaders() async {
        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(
            markdown: "Before",
            loadFileCompletions: { ["Sources/Before.swift"] }
        ))
        let initialProvider = controller.completionProvider

        controller.configure(makeConfiguration(
            markdown: "After",
            loadFileCompletions: { ["Sources/After.swift"] }
        ))
        let suggestions = await controller.completionProvider.suggestions(for: completionContext(
            trigger: .mention,
            query: "After",
            rawQuery: "After"
        ))

        XCTAssertTrue(controller.completionProvider === initialProvider)
        XCTAssertEqual(suggestions.map(\.title), ["Sources/After.swift"])
    }

    func testLocationChangeReplacesCompletionProvider() {
        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(
            markdown: "Before",
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/alveary-project")
        ))
        let initialProvider = controller.completionProvider

        controller.configure(makeConfiguration(
            markdown: "After",
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/other-project")
        ))

        XCTAssertFalse(controller.completionProvider === initialProvider)
    }

    func testFileCompletionHonorsParentDirectoryReference() async {
        let provider = BlockInputComposerCompletionProvider(
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/project/current"),
            loadFileCompletions: {
                [
                    "/tmp/project/current/Sources/App.swift",
                    "/tmp/project/Shared/Config.swift",
                    "/tmp/Other/Ignored.swift"
                ]
            },
            loadSkillCompletions: { [] }
        )
        let suggestions = await provider.suggestions(for: completionContext(
            trigger: .mention,
            query: "Shared",
            rawQuery: "..Shared",
            fileQuery: BlockInputCompletionFileQuery(
                directoryReference: .parent,
                levelsUp: 1,
                remainder: "Shared"
            )
        ))

        XCTAssertEqual(suggestions.map(\.title), ["../Shared/Config.swift"])
        XCTAssertEqual(suggestions.first?.insertionText, "[../Shared/Config.swift](/tmp/project/Shared/Config.swift) ")
    }

    func testFileCompletionUsesRelativeMarkdownLinksInsideEffectiveDirectory() async {
        let provider = BlockInputComposerCompletionProvider(
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/project"),
            loadFileCompletions: {
                ["Sources/App.swift"]
            },
            loadSkillCompletions: { [] }
        )
        let suggestions = await provider.suggestions(for: completionContext(
            trigger: .mention,
            query: "App",
            rawQuery: "App"
        ))

        XCTAssertEqual(suggestions.first?.title, "Sources/App.swift")
        XCTAssertEqual(suggestions.first?.insertionText, "[Sources/App.swift](Sources/App.swift) ")
    }

    func testFileCompletionPreservesSubsequenceMatching() async {
        let provider = BlockInputComposerCompletionProvider(
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/project"),
            loadFileCompletions: {
                ["Sources/AppCoordinator.swift"]
            },
            loadSkillCompletions: { [] }
        )
        let suggestions = await provider.suggestions(for: completionContext(
            trigger: .mention,
            query: "ac",
            rawQuery: "ac"
        ))

        XCTAssertEqual(suggestions.first?.title, "Sources/AppCoordinator.swift")
    }

    func testSkillCompletionUsesRawSlashCommandWithExactMatchText() async {
        let provider = BlockInputComposerCompletionProvider(
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/project"),
            loadFileCompletions: { [] },
            loadSkillCompletions: {
                [
                    Skill(
                        id: "build",
                        name: "build",
                        description: "Build the project",
                        version: nil,
                        source: .local,
                        isInstalled: true,
                        syncedAgentIDs: [],
                        owner: nil,
                        repo: nil,
                        sourceUrl: nil,
                        installs: nil
                    )
                ]
            }
        )
        let suggestions = await provider.suggestions(for: completionContext(
            trigger: .slashCommand,
            query: "b",
            rawQuery: "b"
        ))

        XCTAssertEqual(suggestions.first?.insertionText, "/build ")
        XCTAssertEqual(suggestions.first?.exactMatchText, "/build")
        XCTAssertEqual(suggestions.first?.trigger, .slashCommand)
    }

    func testSkillCompletionPreservesSubsequenceMatching() async {
        let provider = BlockInputComposerCompletionProvider(
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/project"),
            loadFileCompletions: { [] },
            loadSkillCompletions: {
                [
                    Skill(
                        id: "build",
                        name: "build",
                        description: "Build the project",
                        version: nil,
                        source: .local,
                        isInstalled: true,
                        syncedAgentIDs: [],
                        owner: nil,
                        repo: nil,
                        sourceUrl: nil,
                        installs: nil
                    )
                ]
            }
        )
        let suggestions = await provider.suggestions(for: completionContext(
            trigger: .slashCommand,
            query: "bd",
            rawQuery: "bd"
        ))

        XCTAssertEqual(suggestions.first?.insertionText, "/build ")
    }

    private func makeConfiguration(
        markdown: String,
        markdownRevision: Int = 0,
        keyboardShortcuts: [BlockInputKeyboardShortcut: BlockInputKeyboardShortcutHandler] = [:],
        onDocumentMutation: @escaping (BlockInputDocumentChange, Bool) -> Void = { _, _ in },
        location: BlockInputComposerLocation = BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/alveary-project"),
        loadFileCompletions: @escaping @Sendable () async -> [String] = { [] },
        loadSkillCompletions: @escaping @Sendable () async -> [Skill] = { [] }
    ) -> BlockInputComposerBridgeConfiguration {
        BlockInputComposerBridgeConfiguration(
            markdown: markdown,
            markdownRevision: markdownRevision,
            location: location,
            loadFileCompletions: loadFileCompletions,
            loadSkillCompletions: loadSkillCompletions,
            keyboardShortcuts: keyboardShortcuts,
            onDocumentMutation: onDocumentMutation
        )
    }

    private func completionContext(
        trigger: BlockInputCompletionTrigger,
        query: String,
        rawQuery: String,
        fileQuery: BlockInputCompletionFileQuery? = nil
    ) -> BlockInputCompletionContext {
        let block = BlockInputBlock(text: "")
        return BlockInputCompletionContext(
            trigger: trigger,
            query: query,
            document: BlockInputDocument(blocks: [block]),
            blockID: block.id,
            rawQuery: rawQuery,
            fileQuery: fileQuery
        )
    }
}
