import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

/// `queueOrSendRelayedPrompt` is how `send_prompt_to_thread` posts into this conversation. These
/// lock the two things that make it different from the composer's send: the model hears the
/// transport text while the transcript keeps the visible one, and nothing the user has staged
/// here rides out with a message that came from elsewhere.
@MainActor
extension ConversationViewModelTests {
    func testRelayedPromptSendsTransportTextAndPersistsVisibleTextWhenIdle() async throws {
        let fixture = try ConversationViewModelTestFixture()

        let delivery = try await fixture.viewModel.queueOrSendRelayedPrompt(Self.relayedOutbound)

        XCTAssertEqual(delivery, .sent)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, [Self.relayedTransportText])
        let row = try XCTUnwrap(fixture.userMessages().first)
        XCTAssertEqual(row.content, Self.relayedVisibleText)
        XCTAssertEqual(row.relayedFromConversationId, "planner-main")
        XCTAssertEqual(row.relayedFromThreadName, "Planner")
        XCTAssertNil(fixture.viewModel.messageQueue.peekNext())
        // The sender renders as a note above the bubble rather than inside the prompt.
        guard case .transcriptNote(_, .relayedPrompt(let threadName))? = fixture.viewModel.state.grouper.items.first else {
            return XCTFail("Expected a relayed-prompt note, got \(fixture.viewModel.state.grouper.items)")
        }
        XCTAssertEqual(threadName, "Planner")
    }

    func testRelayedPromptQueuesBehindABusyTurnWithoutTakingStagedAttachments() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let staged = LocalImageAttachment(
            id: "staged-image",
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("diagram.png"),
            label: "diagram.png",
            createdAt: Date()
        )
        fixture.viewModel.state.stagedImageAttachments = [staged]
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)
        fixture.viewModel.turnState.beginTurn()

        let delivery = try await fixture.viewModel.queueOrSendRelayedPrompt(Self.relayedOutbound)

        XCTAssertEqual(delivery, .queued)
        let queued = try XCTUnwrap(fixture.viewModel.messageQueue.peekNext())
        XCTAssertEqual(fixture.viewModel.messageQueue.pending.count, 1)
        XCTAssertEqual(queued.text, Self.relayedVisibleText)
        XCTAssertEqual(queued.transportText, Self.relayedTransportText)
        XCTAssertEqual(queued.relayedFrom, Self.relayedAttribution)
        XCTAssertTrue(queued.attachments.isEmpty)
        XCTAssertEqual(fixture.viewModel.state.stagedImageAttachments, [staged])
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    /// The drain drops only plan-revision transport text that went stale; a relayed prompt's
    /// sender header has to survive the wait, or the model gets the visible text and no
    /// `thread_id` to answer.
    func testQueuedRelayedPromptDrainsWithItsTransportText() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.activateViewLifecycle()
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)
        fixture.viewModel.turnState.beginTurn()
        let delivery = try await fixture.viewModel.queueOrSendRelayedPrompt(Self.relayedOutbound)
        XCTAssertEqual(delivery, .queued)

        await fixture.agentsManager.setStatus(.idle, for: fixture.conversation.id)
        fixture.viewModel.handleTurnCompleted()

        try await waitUntil("queued relayed prompt drained") {
            await fixture.agentsManager.sentMessages() == [Self.relayedTransportText] &&
                fixture.viewModel.messageQueue.peekNext() == nil
        }
        let row = try XCTUnwrap(fixture.userMessages().first)
        XCTAssertEqual(row.content, Self.relayedVisibleText)
        XCTAssertEqual(row.relayedFromThreadName, "Planner")
    }

    func testRelayedPromptIsRefusedDuringASessionHandoff() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.viewModel.startSessionHandoff(trigger: .manual)
        try await waitUntil("handoff prompt sent") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }
        fixture.viewModel.handleEvent(.error(message: "handoff prompt failed"))
        XCTAssertTrue(fixture.viewModel.state.hasActiveSessionHandoff)

        do {
            _ = try await fixture.viewModel.queueOrSendRelayedPrompt(Self.relayedOutbound)
            XCTFail("Expected the relayed prompt to be refused")
        } catch {
            XCTAssertEqual(error as? AgentError, AgentError.spawnFailed("Session handoff is in progress"))
        }
        XCTAssertNil(fixture.viewModel.messageQueue.peekNext())
    }

    private static let relayedVisibleText = "Summarize your progress."
    private static let relayedTransportText = "[Sent by the Alveary thread \"Planner\" (thread_id: planner-main).]" +
        "\n\nSummarize your progress."
    private static let relayedAttribution = RelayedPromptAttribution(conversationID: "planner-main", threadName: "Planner")
    private static var relayedOutbound: OutboundMessageText {
        OutboundMessageText(
            visibleText: relayedVisibleText,
            transportText: relayedTransportText,
            relayedFrom: relayedAttribution
        )
    }
}
