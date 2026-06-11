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
            localCommands: ComposerLocalCommandAvailability(supportsSpeedMode: true, supportsSessionHandoff: true),
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] }
        )

        let handoffSuggestions = await provider.suggestions(for: Self.completionContext(query: "/h"))
        let fastSuggestions = await provider.suggestions(for: Self.completionContext(query: "/f"))

        XCTAssertEqual(handoffSuggestions.first?.insertionText, "/handoff ")
        XCTAssertEqual(handoffSuggestions.first?.detailText, "Alveary")
        XCTAssertEqual(fastSuggestions.first?.insertionText, "/fast ")
        XCTAssertEqual(fastSuggestions.first?.detailText, "Alveary")
    }

    func testPassthroughCommandCompletionSuppressesConflictingSkill() async {
        let provider = BlockInputComposerCompletionProvider(
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/project"),
            passthroughSlashCommands: [Self.compactCommand],
            loadFileCompletions: { [] },
            loadSkillCompletions: {
                [
                    Self.skill(id: "compact", name: "compact", description: "External compact skill"),
                    Self.skill(id: "build", name: "build", description: "Build the project")
                ]
            }
        )
        let suggestions = await provider.suggestions(for: Self.completionContext(query: "c"))

        XCTAssertEqual(suggestions.first?.id, "alveary://provider-commands/claude/compact")
        XCTAssertEqual(suggestions.first?.insertionText, "/compact ")
        XCTAssertEqual(suggestions.first?.detailText, "Claude")
        XCTAssertFalse(suggestions.dropFirst().contains { $0.subtitle == "External compact skill" })
    }

    func testInactivePassthroughCommandDoesNotSuppressSkill() async {
        let provider = BlockInputComposerCompletionProvider(
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/project"),
            passthroughSlashCommands: [],
            loadFileCompletions: { [] },
            loadSkillCompletions: {
                [
                    Self.skill(id: "compact", name: "compact", description: "External compact skill")
                ]
            }
        )
        let suggestions = await provider.suggestions(for: Self.completionContext(query: "c"))

        XCTAssertEqual(suggestions.map(\.insertionText), ["/compact "])
        XCTAssertEqual(suggestions.first?.subtitle, "External compact skill")
    }

    func testSameLocationReconfigureUsesLatestPassthroughSlashCommands() async {
        let configuration = Self.bridgeConfiguration(markdown: "Before")
        let controller = BlockInputComposerBridgeController(configuration: configuration)
        let initialProvider = controller.completionProvider

        controller.configure(Self.bridgeConfiguration(
            markdown: "After",
            passthroughSlashCommands: [Self.compactCommand]
        ))
        let suggestions = await controller.completionProvider.suggestions(for: Self.completionContext(query: "compact"))

        XCTAssertTrue(controller.completionProvider === initialProvider)
        XCTAssertEqual(suggestions.map(\.insertionText), ["/compact "])
        XCTAssertEqual(suggestions.first?.detailText, "Claude")
    }

    nonisolated private static var compactCommand: ComposerPassthroughSlashCommand {
        ComposerPassthroughSlashCommand(
            command: "compact",
            subtitle: "Compact context",
            detailText: "Claude",
            uri: "alveary://provider-commands/claude/compact",
            argumentHint: "Optional compact instructions"
        )
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

    private static func bridgeConfiguration(
        markdown: String,
        passthroughSlashCommands: [ComposerPassthroughSlashCommand] = []
    ) -> BlockInputComposerBridgeConfiguration {
        BlockInputComposerBridgeConfiguration(
            markdown: markdown,
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/alveary-project"),
            passthroughSlashCommands: passthroughSlashCommands,
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] }
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
