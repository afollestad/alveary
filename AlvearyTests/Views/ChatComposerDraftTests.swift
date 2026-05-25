import XCTest

@testable import Alveary

@MainActor
final class ChatComposerDraftTests: XCTestCase {
    func testLegacyDraftKeepsOutboundMentionRewrite() {
        let draft = ComposerDraft(
            text: "Please read @/tmp/alveary/project/My%20Notes.md",
            source: .legacyText
        )

        XCTAssertEqual(
            draft.outboundMessage(workingDirectory: "/tmp/alveary/project"),
            "Please read @My%20Notes.md"
        )
    }

    func testBlockInputMarkdownDraftSendsMarkdownDirectly() {
        let markdown = "Please read [My Notes](/tmp/alveary/project/My%20Notes.md)"
        let draft = ComposerDraft(text: markdown, source: .blockInputMarkdown)

        XCTAssertEqual(draft.outboundMessage(workingDirectory: "/tmp/alveary/project"), markdown)
    }

    func testBlockInputMarkdownDraftUsesBlockInputEmptiness() {
        let draft = ComposerDraft(text: "```\n", source: .blockInputMarkdown)

        XCTAssertTrue(draft.isEffectivelyEmpty)
    }
}
