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
