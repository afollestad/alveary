import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
extension BlockInputComposerBridgeControllerTests {
    func testLocalCommandCompletionSortsBeforeSkillsAndSuppressesConflicts() async {
        let provider = BlockInputComposerCompletionProvider(
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/project"),
            localCommands: ComposerLocalCommandAvailability(supportsPlanMode: true, supportsSessionHandoff: true),
            loadFileCompletions: { [] },
            loadSkillCompletions: {
                [
                    Self.skill(id: "plan", name: "plan", description: "External plan skill"),
                    Self.skill(id: "build", name: "build", description: "Build the project")
                ]
            }
        )
        let suggestions = await provider.suggestions(for: Self.completionContext(query: "p"))

        XCTAssertEqual(suggestions.first?.insertionText, "/plan ")
        XCTAssertEqual(suggestions.first?.detailText, "Alveary")
        XCTAssertFalse(suggestions.dropFirst().contains { $0.subtitle == "External plan skill" })
    }

    func testInactiveLocalCommandDoesNotSuppressSkill() async {
        let provider = BlockInputComposerCompletionProvider(
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/project"),
            localCommands: ComposerLocalCommandAvailability(supportsPlanMode: false, supportsSessionHandoff: false),
            loadFileCompletions: { [] },
            loadSkillCompletions: {
                [
                    Self.skill(id: "plan", name: "plan", description: "External plan skill")
                ]
            }
        )
        let suggestions = await provider.suggestions(for: Self.completionContext(query: "p"))

        XCTAssertEqual(suggestions.map(\.insertionText), ["/plan "])
        XCTAssertEqual(suggestions.first?.subtitle, "External plan skill")
    }

    func testLocalCommandCompletionMatchesSlashPrefixedQuery() async {
        let provider = BlockInputComposerCompletionProvider(
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/project"),
            localCommands: ComposerLocalCommandAvailability(supportsSessionHandoff: true),
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] }
        )

        let suggestions = await provider.suggestions(for: Self.completionContext(query: "/h"))

        XCTAssertEqual(suggestions.first?.insertionText, "/handoff ")
        XCTAssertEqual(suggestions.first?.detailText, "Alveary")
    }

    nonisolated private static func skill(id: String, name: String, description: String) -> Skill {
        Skill(
            id: id,
            name: name,
            description: description,
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

    private static func completionContext(query: String) -> BlockInputCompletionContext {
        let block = BlockInputBlock(text: "")
        return BlockInputCompletionContext(
            trigger: .slashCommand,
            query: query,
            document: BlockInputDocument(blocks: [block]),
            blockID: block.id,
            rawQuery: query
        )
    }
}
