import AppKit
import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
final class BlockInputComposerArgumentHintTests: XCTestCase {
    func testProjectPinsBlockInputKitArgumentHintSupportCommit() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectYAML = try String(
            contentsOf: repositoryRoot.appendingPathComponent("project.yml"),
            encoding: .utf8
        )

        XCTAssertTrue(projectYAML.contains(#"revision: "7726331c5e28f0c475382e1c245166ca48b25370""#))
    }

    func testBridgeInlineHintProviderDisplaysCachedSkillArgumentHint() async {
        let controller = BlockInputComposerBridgeController(configuration: makeConfiguration(
            markdown: "",
            loadSkillCompletions: {
                [Self.skill(id: "review-github-pr", name: "review-github-pr", argumentHint: "[PR URL]")]
            }
        ))

        _ = await controller.completionProvider.suggestions(for: completionContext(
            trigger: .slashCommand,
            query: "review",
            rawQuery: "review"
        ))
        let blockInputConfiguration = controller.blockInputConfiguration(for: makeConfiguration(markdown: ""))

        XCTAssertEqual(
            blockInputConfiguration.inlineHintProvider?(inlineHintContext(text: "/review-github-pr"))?.text,
            " [PR URL]"
        )
    }

    func testSkillCompletionCachesArgumentHintsForNamesAndIDs() async {
        let provider = BlockInputComposerCompletionProvider(
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/project"),
            loadFileCompletions: { [] },
            loadSkillCompletions: {
                [
                    Self.skill(id: "skill-123", name: "review-github-pr", argumentHint: "[PR URL]"),
                    Self.skill(id: "deploy", name: "deploy", argumentHint: "Environment")
                ]
            }
        )

        XCTAssertNil(provider.inlineHint(for: inlineHintContext(text: "/review-github-pr")))

        _ = await provider.suggestions(for: completionContext(
            trigger: .slashCommand,
            query: "review",
            rawQuery: "review"
        ))

        XCTAssertEqual(provider.inlineHint(for: inlineHintContext(text: "/review-github-pr"))?.text, " [PR URL]")
        XCTAssertEqual(provider.inlineHint(for: inlineHintContext(text: "/skill-123 "))?.text, "[PR URL]")
    }

    func testSkillArgumentHintHidesForArgumentsNewlineSelectionCaretAndNonStartBlocks() async {
        let provider = BlockInputComposerCompletionProvider(
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/project"),
            loadFileCompletions: { [] },
            loadSkillCompletions: {
                [Self.skill(id: "review-github-pr", name: "review-github-pr", argumentHint: "[PR URL]")]
            }
        )

        _ = await provider.suggestions(for: completionContext(
            trigger: .slashCommand,
            query: "review",
            rawQuery: "review"
        ))

        XCTAssertNil(provider.inlineHint(for: inlineHintContext(text: "/review-github-pr https://example.com")))
        XCTAssertNil(provider.inlineHint(for: inlineHintContext(text: "/review-github-pr\n")))
        XCTAssertNil(provider.inlineHint(for: inlineHintContext(
            text: "/review-github-pr",
            selectedRange: NSRange(location: 0, length: 1)
        )))
        XCTAssertNil(provider.inlineHint(for: inlineHintContext(text: "/review-github-pr", cursorOffset: 7)))
        XCTAssertNil(provider.inlineHint(for: inlineHintContext(text: "/review-github-pr", blockIndex: 1)))
    }

    func testSkillArgumentHintCachePreservesAcrossSameLocationUpdateAndRefreshesAfterLaterLoad() async {
        let loadedSkills = LockedState([
            Self.skill(id: "review-github-pr", name: "review-github-pr", argumentHint: "[PR URL]")
        ])
        let provider = BlockInputComposerCompletionProvider(
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/project"),
            loadFileCompletions: { [] },
            loadSkillCompletions: { loadedSkills.withLock { $0 } }
        )

        _ = await provider.suggestions(for: completionContext(
            trigger: .slashCommand,
            query: "review",
            rawQuery: "review"
        ))
        provider.update(
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/project"),
            loadFileCompletions: { [] },
            loadSkillCompletions: { loadedSkills.withLock { $0 } }
        )
        loadedSkills.withLock { skills in
            skills = [
                Self.skill(id: "deploy", name: "deploy", argumentHint: "Environment")
            ]
        }

        XCTAssertEqual(provider.inlineHint(for: inlineHintContext(text: "/review-github-pr"))?.text, " [PR URL]")

        _ = await provider.suggestions(for: completionContext(
            trigger: .slashCommand,
            query: "deploy",
            rawQuery: "deploy"
        ))

        XCTAssertNil(provider.inlineHint(for: inlineHintContext(text: "/review-github-pr")))
        XCTAssertEqual(provider.inlineHint(for: inlineHintContext(text: "/deploy"))?.text, " Environment")
    }

    private func makeConfiguration(
        markdown: String,
        loadSkillCompletions: @escaping @Sendable () async -> [Skill] = { [] }
    ) -> BlockInputComposerBridgeConfiguration {
        BlockInputComposerBridgeConfiguration(
            markdown: markdown,
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/alveary-project"),
            loadFileCompletions: { [] },
            loadSkillCompletions: loadSkillCompletions
        )
    }

    private func completionContext(
        trigger: BlockInputCompletionTrigger,
        query: String,
        rawQuery: String
    ) -> BlockInputCompletionContext {
        let block = BlockInputBlock(text: "")
        return BlockInputCompletionContext(
            trigger: trigger,
            query: query,
            document: BlockInputDocument(blocks: [block]),
            blockID: block.id,
            rawQuery: rawQuery
        )
    }

    private func inlineHintContext(
        text: String,
        blockIndex: Int = 0,
        selectedRange: NSRange? = nil,
        cursorOffset: Int? = nil
    ) -> BlockInputInlineHintContext {
        let block = BlockInputBlock(id: "block", text: text)
        let offset = cursorOffset ?? (text as NSString).length
        return BlockInputInlineHintContext(
            editorView: BlockInputView(),
            block: block,
            blockIndex: blockIndex,
            cursor: BlockInputCursor(blockID: block.id, utf16Offset: offset),
            selectedRange: selectedRange ?? NSRange(location: offset, length: 0),
            isDocumentStartBlock: blockIndex == 0,
            isAtDocumentStart: blockIndex == 0 && offset == 0
        )
    }

    nonisolated private static func skill(
        id: String,
        name: String,
        argumentHint: String? = nil
    ) -> Skill {
        Skill(
            id: id,
            name: name,
            description: "\(name) description",
            argumentHint: argumentHint,
            version: nil,
            source: .local,
            isInstalled: true,
            syncedAgentIDs: [],
            owner: nil,
            repo: nil,
            sourceUrl: nil,
            installs: nil
        )
    }
}
