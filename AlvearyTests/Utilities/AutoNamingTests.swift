import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
final class AutoNamingTests: XCTestCase {
    func testAgentThreadNamingHelpersRespectManualRenameState() {
        let untitled = AgentThread(name: AgentThread.untitledName)
        let manuallyUntitled = AgentThread(name: AgentThread.untitledName, hasCustomName: true)
        let renamed = AgentThread(name: "  Investigate auth race  ", hasCustomName: true)
        let blank = AgentThread(name: "   ")

        XCTAssertTrue(untitled.isEffectivelyUntitled)
        XCTAssertFalse(manuallyUntitled.isEffectivelyUntitled)
        XCTAssertFalse(renamed.isEffectivelyUntitled)
        XCTAssertEqual(renamed.displayName(), "Investigate auth race")
        XCTAssertEqual(blank.displayName(), AgentThread.untitledName)
        XCTAssertEqual(AgentThread.persistedName(from: "  Investigate auth race  "), "Investigate auth race")
        XCTAssertNil(AgentThread.persistedName(from: "   "))
    }

    func testSessionPreviewRejectsShortMessagesConfirmationsAndCommands() {
        XCTAssertNil(AgentSessionPreviewGenerator.preview(fromInitialPrompt: "Short"))
        XCTAssertNil(AgentSessionPreviewGenerator.preview(fromInitialPrompt: "yes"))
        XCTAssertNil(AgentSessionPreviewGenerator.preview(fromInitialPrompt: "/commit"))
    }

    func testSessionPreviewAllowsLongerMessagesThatContainConfirmationWords() {
        XCTAssertEqual(
            AgentSessionPreviewGenerator.preview(fromInitialPrompt: "yes please fix the auth bug"),
            "yes please fix the auth bug"
        )
    }

    func testSessionPreviewTruncatesAtWordBoundary() {
        let message = "Implement a really long authentication fix for the session manager regression today"

        XCTAssertEqual(
            AgentSessionPreviewGenerator.preview(fromInitialPrompt: message),
            "Implement a really long authentication fix for..."
        )
    }

    func testSessionPreviewFallsBackToHardTruncationWithoutWordBoundary() {
        let message = String(repeating: "a", count: 60)

        XCTAssertEqual(
            AgentSessionPreviewGenerator.preview(fromInitialPrompt: message),
            String(repeating: "a", count: 50) + "..."
        )
    }

    /// A composer file mention is a Markdown link labelled with the whole repo-relative path, which used to fill the
    /// preview budget on its own and leave the thread titled `In...`.
    func testSessionPreviewCompactsFileMentionPathToFileName() {
        let path = "local/views/src/main/kotlin/app/cash/local/views/brand/profile/v2/content/tabs/" +
            "LocalBrandProfileV2ContentAboutTab.kt"

        XCTAssertEqual(
            AgentSessionPreviewGenerator.preview(
                fromInitialPrompt: "In [\(path)](\(path)) the `CenteredDividedChip` doesn't center its inner Row"
            ),
            "In LocalBrandProfileV2ContentAboutTab.kt the..."
        )
    }

    /// The composer labels a mention with an absolute path whenever the user's query started at `/`, and the
    /// generator's slash-command guard reads the *flattened* text — so before the label compacted to its file name, a
    /// message opening with one looked like `/command` and suppressed the title entirely.
    func testSessionPreviewTitlesAMessageOpeningWithAnAbsolutePathMention() {
        let path = "/Users/me/Development/project/Sources/SomeVeryLongFileName.swift"

        XCTAssertEqual(
            AgentSessionPreviewGenerator.preview(fromInitialPrompt: "[\(path)](\(path)) needs the parser fix"),
            "SomeVeryLongFileName.swift needs the parser fix"
        )
    }

    func testSessionPreviewReplacesHTMLImageTagBeforeTruncating() {
        XCTAssertEqual(
            AgentSessionPreviewGenerator.preview(
                fromInitialPrompt: #"<img src="file:///tmp/photo.jpg" alt="Photo" width="262" height="174" />"#
            ),
            "(Image)"
        )
    }

    func testSessionPreviewStripsHTMLTagsBeforeTruncating() {
        XCTAssertEqual(
            AgentSessionPreviewGenerator.preview(fromInitialPrompt: #"<div class="note">Title <span>body</span></div>"#),
            "Title body"
        )
    }

    func testSessionPreviewRejectsShortContentAfterStrippingHTMLTags() {
        XCTAssertNil(AgentSessionPreviewGenerator.preview(fromInitialPrompt: "<div>hi</div>"))
    }

    func testSessionPreviewPreservesHTMLLikeTextInsideInlineCode() {
        XCTAssertEqual(
            AgentSessionPreviewGenerator.preview(fromInitialPrompt: "Fix `Array<String>` now"),
            "Fix `Array<String>` now"
        )
    }

    func testPromptFormattingHelpersProduceStableStrings() {
        let answers = [
            (question: " Language ", answer: "Swift"),
            (question: "Framework", answer: "SwiftUI")
        ]

        XCTAssertEqual(
            ConversationViewModel.formatPromptAnswers(answers: answers),
            "For the question ' Language ': Swift\nFor the question 'Framework': SwiftUI"
        )
        XCTAssertEqual(
            ConversationViewModel.promptSummary(answers: answers),
            "Q: Language\nA: Swift\n\nQ: Framework\nA: SwiftUI"
        )
    }
}
