import XCTest

@testable import Skep

@MainActor
final class AutoNamingTests: XCTestCase {
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
            "Language: Swift\nFramework: SwiftUI"
        )
    }
}
