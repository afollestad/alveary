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
        XCTAssertEqual(blockInputConfiguration.completionPopupConfiguration.placement, .caret)
        XCTAssertEqual(blockInputConfiguration.heightSizing?.defaultVisibleLineCount, 3)
        XCTAssertEqual(blockInputConfiguration.heightSizing?.maximumVisibleLineCount, 9)
        XCTAssertEqual(blockInputConfiguration.fileBaseURL?.path, CanonicalPath.normalize("/tmp/alveary-project"))
        XCTAssertEqual(blockInputConfiguration.imageBaseURL?.path, CanonicalPath.normalize("/tmp/alveary-project"))
    }

    func testBridgeReplacesExternalMarkdownAndResetsUndo() {
        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(markdown: "Before"))
        let initialUndoController = controller.undoController

        controller.configure(makeConfiguration(markdown: "After", markdownRevision: 1))

        XCTAssertEqual(controller.currentMarkdown(), "After")
        XCTAssertFalse(controller.undoController === initialUndoController)
    }

    func testDocumentChangeUpdatesBridgeMarkdownMirror() {
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

    func testCoalescedPublishDoesNotResetUndoForMirroredDocument() {
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
        XCTAssertEqual(suggestions.first?.insertionText, "[../Shared/Config.swift](/tmp/project/Shared/Config.swift)")
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
        XCTAssertEqual(suggestions.first?.insertionText, "[Sources/App.swift](Sources/App.swift)")
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
        markdownRevision: Int = 0
    ) -> BlockInputComposerBridgeConfiguration {
        BlockInputComposerBridgeConfiguration(
            markdown: markdown,
            markdownRevision: markdownRevision,
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/alveary-project"),
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] }
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
