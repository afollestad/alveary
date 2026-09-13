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
