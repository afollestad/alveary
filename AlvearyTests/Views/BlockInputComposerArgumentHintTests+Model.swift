import AppKit
import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
extension BlockInputComposerArgumentHintTests {
    func testModelHintListsShortNamesAcrossProviders() {
        let provider = makeProvider(modelOptions: [
            Self.modelOption(providerID: "claude", value: "sonnet", shortName: "sonnet", title: "Sonnet"),
            Self.modelOption(providerID: "codex", value: "gpt-5.6-sol", shortName: "sol", title: "GPT-5.6-Sol")
        ])

        XCTAssertEqual(provider.inlineHint(for: modelHintContext(text: "/model"))?.text, " sonnet|sol")
        XCTAssertEqual(provider.inlineHint(for: modelHintContext(text: "/model "))?.text, "sonnet|sol")
    }

    func testModelHintTruncatesLongProviderListsWithEllipsis() {
        let provider = makeProvider(modelOptions: [
            Self.modelOption(providerID: "claude", value: "sonnet", shortName: "sonnet", title: "Sonnet"),
            Self.modelOption(providerID: "claude", value: "fable", shortName: "fable", title: "Fable"),
            Self.modelOption(providerID: "claude", value: "opus", shortName: "opus", title: "Opus"),
            Self.modelOption(providerID: "claude", value: "haiku", shortName: "haiku", title: "Haiku"),
            // Codex ids that earn no alias stay long, which is what pushes the hint over its budget.
            Self.modelOption(providerID: "codex", value: "gpt-5.4-mini", shortName: "gpt-5.4-mini", title: "GPT-5.4-Mini"),
            Self.modelOption(providerID: "codex", value: "gpt-5.5", shortName: "gpt-5.5", title: "GPT-5.5")
        ])

        let hint = provider.inlineHint(for: modelHintContext(text: "/model "))?.text

        XCTAssertEqual(hint, "sonnet|fable|opus|haiku|gpt-5.4-mini|…")
    }

    func testModelHintIsAbsentWithFewerThanTwoOptions() {
        let provider = makeProvider(modelOptions: [
            Self.modelOption(providerID: "claude", value: "sonnet", shortName: "sonnet", title: "Sonnet")
        ])

        XCTAssertNil(provider.inlineHint(for: modelHintContext(text: "/model")))
    }

    func testModelHintUpdatesWhenModelOptionsChange() {
        let provider = makeProvider(modelOptions: [
            Self.modelOption(providerID: "claude", value: "sonnet", shortName: "sonnet", title: "Sonnet"),
            Self.modelOption(providerID: "claude", value: "opus", shortName: "opus", title: "Opus")
        ])

        XCTAssertEqual(provider.inlineHint(for: modelHintContext(text: "/model"))?.text, " sonnet|opus")

        provider.update(
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/project"),
            localCommands: ComposerLocalCommandAvailability(modelOptions: [
                Self.modelOption(providerID: "codex", value: "gpt-5.6-sol", shortName: "sol", title: "GPT-5.6-Sol"),
                Self.modelOption(providerID: "codex", value: "gpt-5.6-luna", shortName: "luna", title: "GPT-5.6-Luna")
            ]),
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] }
        )

        XCTAssertEqual(provider.inlineHint(for: modelHintContext(text: "/model"))?.text, " sol|luna")
    }

    func testModelHintIsSuppressedWithSlashCommandSuggestions() async {
        let provider = BlockInputComposerCompletionProvider(
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/project"),
            localCommands: ComposerLocalCommandAvailability(
                modelOptions: [
                    Self.modelOption(providerID: "claude", value: "sonnet", shortName: "sonnet", title: "Sonnet"),
                    Self.modelOption(providerID: "claude", value: "opus", shortName: "opus", title: "Opus")
                ],
                suppressesSlashCommandSuggestions: true
            ),
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] }
        )

        XCTAssertNil(provider.inlineHint(for: modelHintContext(text: "/model")))
    }

    private func makeProvider(
        modelOptions: [ComposerModelCommandOption]
    ) -> BlockInputComposerCompletionProvider {
        BlockInputComposerCompletionProvider(
            location: BlockInputComposerLocation(effectiveProjectDirectory: "/tmp/project"),
            localCommands: ComposerLocalCommandAvailability(modelOptions: modelOptions),
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] }
        )
    }

    private func modelHintContext(text: String) -> BlockInputInlineHintContext {
        let block = BlockInputBlock(id: "block", text: text)
        let offset = (text as NSString).length
        return BlockInputInlineHintContext(
            editorView: BlockInputView(),
            block: block,
            blockIndex: 0,
            cursor: BlockInputCursor(blockID: block.id, utf16Offset: offset),
            selectedRange: NSRange(location: offset, length: 0),
            isDocumentStartBlock: true,
            isAtDocumentStart: offset == 0
        )
    }

    nonisolated static func modelOption(
        providerID: String,
        value: String,
        shortName: String,
        title: String
    ) -> ComposerModelCommandOption {
        ComposerModelCommandOption(providerID: providerID, value: value, shortName: shortName, title: title)
    }
}
