import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// The delivery half of `send_prompt_to_thread`, driven through a real controller registry over
/// the mock runtime: what a headless send must do that the composer's send gets from its view.
@MainActor
final class HeadlessRelayedPromptDeliveryTests: XCTestCase {
    /// A background controller starts with an empty grouper. Without hydration the relayed turn's
    /// live events would advance the cursor past the history, and the next mount's incremental
    /// rebuild would append that history after them.
    func testHydratesHistoryBeforeSendingSoAMountAppendsNothingTwice() async throws {
        let fixture = try ConversationViewModelTestFixture()
        try insertHistory(into: fixture)
        let registry = makeRegistry(fixture)

        let delivery = try await HeadlessRelayedPromptDelivery.deliver(
            Self.outbound,
            into: fixture.conversation,
            registry: registry
        )

        XCTAssertEqual(delivery, .sent)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, [Self.transportText])
        XCTAssertEqual(texts(of: fixture), ["Earlier question", "Earlier answer", Self.visibleText])
        XCTAssertEqual(fixture.viewModel.state.grouper.processedCount, 3)

        // The rebuild a later mount performs must find nothing left to append.
        fixture.viewModel.rebuildChatItemsFromConversationRecords()
        XCTAssertEqual(texts(of: fixture), ["Earlier question", "Earlier answer", Self.visibleText])
        XCTAssertEqual(fixture.viewModel.state.grouper.processedCount, 3)
        registry.invalidate(for: ConversationControllerKey(conversation: fixture.conversation))
    }

    /// Nobody is looking at the target, so the queued prompt has only this delivery's lease to
    /// keep a controller lifecycle active long enough to drain it.
    func testQueuedPromptDrainsAfterTheBusyTurnEndsWithNoWindow() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let registry = makeRegistry(fixture)
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)
        fixture.viewModel.turnState.beginTurn()

        let delivery = try await HeadlessRelayedPromptDelivery.deliver(
            Self.outbound,
            into: fixture.conversation,
            registry: registry
        )

        XCTAssertEqual(delivery, .queued)
        XCTAssertEqual(fixture.viewModel.messageQueue.peekNext()?.text, Self.visibleText)
        let sentBeforeTurnEnd = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentBeforeTurnEnd.isEmpty)

        await fixture.agentsManager.setStatus(.idle, for: fixture.conversation.id)
        fixture.viewModel.handleTurnCompleted()

        try await waitUntil("queued relayed prompt sent headlessly") {
            await fixture.agentsManager.sentMessages() == [Self.transportText] &&
                fixture.viewModel.messageQueue.peekNext() == nil
        }
        registry.invalidate(for: ConversationControllerKey(conversation: fixture.conversation))
    }

    private static let visibleText = "Summarize your progress."
    private static let transportText = "[Sent by the Alveary thread \"Planner\" (thread_id: planner-main).]" +
        "\n\nSummarize your progress."
    private static var outbound: OutboundMessageText {
        OutboundMessageText(
            visibleText: visibleText,
            transportText: transportText,
            relayedFrom: RelayedPromptAttribution(conversationID: "planner-main", threadName: "Planner")
        )
    }

    private func makeRegistry(_ fixture: ConversationViewModelTestFixture) -> DefaultConversationControllerRegistry {
        DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in },
            runtimeIsSuspended: { _ in true }
        )
    }

    private func insertHistory(into fixture: ConversationViewModelTestFixture) throws {
        let question = ConversationEventRecord(
            id: "history-question",
            conversationId: fixture.conversation.id,
            type: ConversationEventRecord.messageType,
            role: ConversationEventRecord.userRole,
            content: "Earlier question",
            timestamp: Date(timeIntervalSince1970: 1),
            conversation: fixture.conversation
        )
        let answer = ConversationEventRecord(
            id: "history-answer",
            conversationId: fixture.conversation.id,
            type: ConversationEventRecord.messageType,
            role: ConversationEventRecord.assistantRole,
            content: "Earlier answer",
            timestamp: Date(timeIntervalSince1970: 2),
            conversation: fixture.conversation
        )
        fixture.context.insert(question)
        fixture.context.insert(answer)
        try fixture.context.save()
    }

    private func texts(of fixture: ConversationViewModelTestFixture) -> [String] {
        fixture.viewModel.state.grouper.items.compactMap { item in
            switch item {
            case .userMessage(_, let text), .assistantMessage(_, let text):
                text
            default:
                nil
            }
        }
    }
}
