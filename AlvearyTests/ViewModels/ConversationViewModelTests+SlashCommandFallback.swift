import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testZeroTokenSlashCommandNonTerminalUsageDoesNotSynthesizeAssistantNotice() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()

        fixture.viewModel.state.turnState.beginTurn()
        _ = fixture.viewModel.insertLocalUserMessage(
            "/test-command",
            into: conversation
        )

        fixture.viewModel.handleEvent(
            .tokens(
                input: 0,
                output: 0,
                cacheRead: 0,
                isError: false,
                stopReason: nil,
                durationMs: 5,
                costUsd: 0,
                permissionDenials: []
            )
        )

        let persistedEvents = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.conversationId == fixture.conversation.id
        }
        XCTAssertEqual(persistedEvents.filter { $0.role == "assistant" }.count, 0)
        XCTAssertEqual(persistedEvents.filter { $0.type == "tokens" }.count, 1)
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
    }

    func testSyntheticSlashCommandNoticeSuppressesNextIdenticalAssistantMessage() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()

        fixture.viewModel.state.turnState.beginTurn()
        _ = fixture.viewModel.insertLocalUserMessage(
            "/test-command",
            into: conversation
        )

        fixture.viewModel.handleEvent(
            .tokens(
                input: 0,
                output: 0,
                cacheRead: 0,
                isError: false,
                stopReason: nil,
                durationMs: 5,
                costUsd: 0,
                permissionDenials: [],
                isTerminal: true
            )
        )
        fixture.viewModel.handleEvent(.message(
            role: "assistant",
            content: "Unknown command: /test-command",
            parentToolUseId: nil
        ))

        let assistantMessages = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.conversationId == fixture.conversation.id && $0.role == "assistant"
        }
        XCTAssertEqual(assistantMessages.map(\.content), ["Unknown command: /test-command"])
        XCTAssertNil(fixture.viewModel.state.pendingSyntheticAssistantDuplicateText)
    }
}
