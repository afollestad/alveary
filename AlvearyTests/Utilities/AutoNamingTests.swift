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

    func testThreadNameRejectsShortMessagesConfirmationsAndCommands() {
        XCTAssertNil(ConversationViewModel.threadName(from: "Short"))
        XCTAssertNil(ConversationViewModel.threadName(from: "yes"))
        XCTAssertNil(ConversationViewModel.threadName(from: "/commit"))
    }

    func testThreadNameAllowsLongerMessagesThatContainConfirmationWords() {
        XCTAssertEqual(
            ConversationViewModel.threadName(from: "yes please fix the auth bug"),
            "yes please fix the auth bug"
        )
    }

    func testThreadNameTruncatesAtWordBoundary() {
        let message = "Implement a really long authentication fix for the session manager regression today"

        XCTAssertEqual(
            ConversationViewModel.threadName(from: message),
            "Implement a really long authentication fix for..."
        )
    }

    func testThreadNameFallsBackToHardTruncationWithoutWordBoundary() {
        let message = String(repeating: "a", count: 60)

        XCTAssertEqual(
            ConversationViewModel.threadName(from: message),
            String(repeating: "a", count: 50) + "..."
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
