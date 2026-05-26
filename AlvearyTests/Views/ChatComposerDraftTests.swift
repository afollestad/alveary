import XCTest

@testable import Alveary

@MainActor
final class ChatComposerDraftTests: XCTestCase {
    func testLegacyDraftSendsStoredTextDirectly() {
        let draft = ComposerDraft(
            text: "Please read @/tmp/alveary/project/My%20Notes.md",
            source: .legacyText
        )

        XCTAssertEqual(
            draft.messageText,
            "Please read @/tmp/alveary/project/My%20Notes.md"
        )
    }

    func testBlockInputMarkdownDraftSendsMarkdownDirectly() {
        let markdown = "Please read [My Notes](/tmp/alveary/project/My%20Notes.md)"
        let draft = ComposerDraft(text: markdown, source: .blockInputMarkdown)

        XCTAssertEqual(draft.messageText, markdown)
    }

    func testBlockInputMarkdownDraftUsesBlockInputEmptiness() {
        let draft = ComposerDraft(text: "```\n", source: .blockInputMarkdown)

        XCTAssertTrue(draft.isEffectivelyEmpty)
    }
}
