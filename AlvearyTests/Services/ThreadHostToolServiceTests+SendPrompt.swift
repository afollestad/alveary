import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ThreadHostToolServiceTests {
    func testSendPromptRelaysBothTextsAndReportsSent() async throws {
        let fixture = try ThreadHostToolFixture()
        try fixture.insertThread(name: "Target", conversationID: "target-main")

        let result = await fixture.sendPrompt(threadID: "target-main", prompt: "Summarize your progress.")

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["status"], .string("sent"))
        XCTAssertEqual(content["thread_id"], .string("target-main"))
        XCTAssertEqual(content["name"], .string("Target"))
        XCTAssertTrue(result.text.contains("running there now"), result.text)

        let delivered = try XCTUnwrap(fixture.relayedPrompts.delivered.first)
        XCTAssertEqual(fixture.relayedPrompts.delivered.count, 1)
        XCTAssertEqual(delivered.conversationID, "target-main")
        // The row is the prompt; the sender rides beside it for the note, and only the model
        // sees the id and the conditional reply guidance.
        XCTAssertEqual(delivered.outbound.visibleText, "Summarize your progress.")
        XCTAssertEqual(
            delivered.outbound.relayedFrom,
            RelayedPromptAttribution(conversationID: "source-conversation", threadName: "Source thread")
        )
        let transport = try XCTUnwrap(delivered.outbound.transportText)
        XCTAssertTrue(transport.contains("thread_id: source-conversation"), transport)
        XCTAssertTrue(transport.contains("If this message asks for an answer, reply with send_prompt_to_thread"), transport)
        XCTAssertTrue(transport.hasSuffix("\n\nSummarize your progress."), transport)
        XCTAssertTrue(delivered.outbound.attachments.isEmpty)
        XCTAssertTrue(delivered.outbound.appShots.isEmpty)
    }

    func testSendPromptReportsQueuedWhenTheTargetIsBusy() async throws {
        let fixture = try ThreadHostToolFixture()
        try fixture.insertThread(name: "Target", conversationID: "target-main")
        fixture.relayedPrompts.delivery = .queued

        let result = await fixture.sendPrompt(threadID: "target-main", prompt: "Summarize your progress.")

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["status"], .string("queued"))
        XCTAssertTrue(result.text.contains("behind its current turn"), result.text)
    }

    /// Sending to the calling thread would only queue the prompt behind the turn making the call,
    /// and a model answering itself never stops.
    func testSendPromptRefusesTheCallersOwnThread() async throws {
        let fixture = try ThreadHostToolFixture()

        let result = await fixture.sendPrompt(threadID: fixture.conversation.id, prompt: "Keep going.")

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.text, ThreadHostToolServiceError.cannotSendToOwnThread.localizedDescription)
        XCTAssertEqual(try object(result.structuredContent)["status"], .string("error"))
        XCTAssertTrue(fixture.relayedPrompts.delivered.isEmpty)
    }

    /// A thread `list_threads` would not have shown reads as missing rather than as something the
    /// model can learn about by guessing ids.
    func testSendPromptReportsUnlistableThreadsAsMissing() async throws {
        let fixture = try ThreadHostToolFixture()
        let draft = AgentThread(name: "Draft", isDraft: true, mode: .task)
        draft.conversations = [Conversation(id: "draft-main", provider: "codex", thread: draft)]
        fixture.modelContext.insert(draft)
        let forked = AgentThread(name: "Forked", mode: .task)
        forked.conversations = [
            Conversation(id: "forked-main", provider: "codex", thread: forked),
            Conversation(id: "forked-fork", provider: "codex", thread: forked)
        ]
        fixture.modelContext.insert(forked)
        try fixture.modelContext.save()

        for threadID in ["missing-thread", "draft-main", "forked-main"] {
            let result = await fixture.sendPrompt(threadID: threadID, prompt: "Hello.")
            XCTAssertTrue(result.isError, threadID)
            XCTAssertEqual(result.text, ThreadHostToolServiceError.threadNotFound.localizedDescription, threadID)
        }
        XCTAssertTrue(fixture.relayedPrompts.delivered.isEmpty)
    }

    func testSendPromptNamesAnArchivedThread() async throws {
        let fixture = try ThreadHostToolFixture()
        let target = try fixture.insertThread(name: "Target", conversationID: "target-main")
        target.archivedAt = Date(timeIntervalSince1970: 2_000)
        try fixture.modelContext.save()

        let result = await fixture.sendPrompt(threadID: "target-main", prompt: "Hello.")

        XCTAssertTrue(result.isError)
        XCTAssertEqual(
            result.text,
            ThreadHostToolServiceError.threadArchived(name: "Target").localizedDescription
        )
        XCTAssertTrue(fixture.relayedPrompts.delivered.isEmpty)
    }

    /// The receipt is what keeps a retransmitted call from posting the prompt twice.
    func testSendPromptReplaysItsReceiptOnAnExactRetry() async throws {
        let fixture = try ThreadHostToolFixture()
        try fixture.insertThread(name: "Target", conversationID: "target-main")
        fixture.relayedPrompts.delivery = .queued

        let first = await fixture.sendPrompt(threadID: "target-main", prompt: "Summarize your progress.")
        let retry = await fixture.sendPrompt(threadID: "target-main", prompt: "Summarize your progress.")
        let fresh = await fixture.sendPrompt(
            threadID: "target-main",
            prompt: "Summarize your progress.",
            requestID: "request-2"
        )

        XCTAssertFalse(first.isError, first.text)
        XCTAssertEqual(retry.text, first.text)
        XCTAssertEqual(try object(retry.structuredContent)["status"], .string("queued"))
        XCTAssertFalse(fresh.isError, fresh.text)
        XCTAssertEqual(fixture.relayedPrompts.delivered.count, 2)
    }

    /// A refusal at the target — a pending question, say — is the model's to hear about, and no
    /// receipt is kept for it, so the model's next attempt is a real one.
    func testSendPromptReportsADeliveryFailureWithoutARecordedReceipt() async throws {
        let fixture = try ThreadHostToolFixture()
        try fixture.insertThread(name: "Target", conversationID: "target-main")
        fixture.relayedPrompts.failure = RelayFailure()

        let failed = await fixture.sendPrompt(threadID: "target-main", prompt: "Hello.")
        fixture.relayedPrompts.failure = nil
        let retried = await fixture.sendPrompt(threadID: "target-main", prompt: "Hello.")

        XCTAssertTrue(failed.isError)
        XCTAssertEqual(
            failed.text,
            ThreadHostToolServiceError.promptDeliveryFailed(
                threadName: "Target",
                reason: RelayFailure().localizedDescription
            ).localizedDescription
        )
        XCTAssertFalse(retried.isError, retried.text)
        XCTAssertEqual(fixture.relayedPrompts.delivered.count, 1)
    }

    /// Sending back exactly what the target just relayed is the loop seen in the wild — each side
    /// bouncing the same text — so it is refused outright, while a real answer goes through.
    func testSendPromptRefusesEchoingWhatTheTargetJustSent() async throws {
        let fixture = try ThreadHostToolFixture()
        try fixture.insertThread(name: "Target", conversationID: "target-main")
        try fixture.insertUserRows(relayedFrom: "target-main", count: 1, content: "Test")

        let echo = await fixture.sendPrompt(threadID: "target-main", prompt: " Test\n")
        let answer = await fixture.sendPrompt(threadID: "target-main", prompt: "Two of three steps are done.", requestID: "request-2")

        XCTAssertTrue(echo.isError)
        XCTAssertEqual(echo.text, ThreadHostToolServiceError.relayEchoesPrompt(threadName: "Target").localizedDescription)
        XCTAssertFalse(answer.isError, answer.text)
        XCTAssertEqual(fixture.relayedPrompts.delivered.count, 1)
    }

    /// The same prompt to the same thread, over and over, is the other shape a loop takes. Only
    /// the counterpart's copies count, and a message the user typed resets them.
    func testSendPromptRefusesRepeatingOnePromptToTheSameThreadUnattended() async throws {
        let fixture = try ThreadHostToolFixture()
        try fixture.insertThread(name: "Target", conversationID: "target-main")
        try fixture.insertThread(name: "Worker", conversationID: "worker-main")
        let priorCopies = ThreadHostToolService.identicalRelayLimit - 1
        // Codex reports the bare tool name; it must count the same as Claude's prefixed one.
        try fixture.insertSendPromptCalls(to: "target-main", count: priorCopies, qualified: false, prompt: "Status?")
        try fixture.insertSendPromptCalls(to: "worker-main", count: priorCopies + 2, prompt: "Anything new?")

        // The call being handled may already be persisted, still awaiting its result; it must not count.
        try fixture.insertSendPromptCalls(to: "target-main", count: 1, prompt: "Anything new?", unanswered: true)

        let repeated = await fixture.sendPrompt(threadID: "target-main", prompt: "Status?")
        let fresh = await fixture.sendPrompt(threadID: "target-main", prompt: "Anything new?", requestID: "request-2")

        XCTAssertTrue(repeated.isError)
        XCTAssertEqual(
            repeated.text,
            ThreadHostToolServiceError.relayRepeatsPrompt(threadName: "Target", count: priorCopies).localizedDescription
        )
        XCTAssertFalse(fresh.isError, fresh.text)

        try fixture.insertUserRows(relayedFrom: nil, count: 1)
        let afterTyping = await fixture.sendPrompt(threadID: "target-main", prompt: "Status?", requestID: "request-3")

        XCTAssertFalse(afterTyping.isError, afterTyping.text)
        XCTAssertEqual(fixture.relayedPrompts.delivered.count, 2)
    }

    /// Nothing counts rounds: threads are meant to talk unattended, so a long exchange of new
    /// content is never refused.
    func testALongExchangeOfNewContentIsNeverRefused() async throws {
        let fixture = try ThreadHostToolFixture()
        try fixture.insertThread(name: "Target", conversationID: "target-main")
        for round in 0..<20 {
            try fixture.insertUserRows(relayedFrom: "target-main", count: 1, content: "Question \(round)")
            try fixture.insertSendPromptCalls(to: "target-main", count: 1, prompt: "Answer \(round)")
        }

        let result = await fixture.sendPrompt(threadID: "target-main", prompt: "Answer 20")

        XCTAssertFalse(result.isError, result.text)
    }

    /// Threads talking to each other is the point, so a scheduled run gets the same answer a
    /// person does.
    func testSendPromptFromAnAutomatedScheduledRunIsDelivered() async throws {
        let fixture = try ThreadHostToolFixture()
        try fixture.insertThread(name: "Target", conversationID: "target-main")
        fixture.thread.scheduledTaskRun = fixture.attachNonterminalScheduledRun()
        try fixture.modelContext.save()

        let result = await fixture.sendPrompt(threadID: "target-main", prompt: "Summarize your progress.")

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fixture.relayedPrompts.delivered.count, 1)
    }
}

private struct RelayFailure: LocalizedError {
    var errorDescription: String? {
        "Answer the pending question before sending another message"
    }
}

extension ThreadHostToolFixture {
    /// User rows on the calling conversation, appended newest last. `relayedFrom` nil is one the
    /// user typed; a sender id is a prompt relayed from that thread.
    func insertUserRows(relayedFrom senderConversationID: String?, count: Int, content: String? = nil) throws {
        let existing = try modelContext.fetchCount(FetchDescriptor<ConversationEventRecord>())
        for offset in 0..<count {
            modelContext.insert(ConversationEventRecord(
                conversationId: conversation.id,
                type: ConversationEventRecord.messageType,
                role: ConversationEventRecord.userRole,
                content: content ?? (senderConversationID == nil ? "Typed by the user" : "Relayed"),
                relayedFromConversationId: senderConversationID,
                relayedFromThreadName: senderConversationID == nil ? nil : "Sender",
                timestamp: Self.transcriptTimestamp(rowIndex: existing + offset),
                conversation: conversation
            ))
        }
        try modelContext.save()
    }

    /// Every inserted row takes the next slot, so rows always sort in insertion order whichever
    /// helper made them; a call's result takes the half step after it.
    static func transcriptTimestamp(rowIndex: Int, isResult: Bool = false) -> Date {
        Date(timeIntervalSince1970: 10_000 + Double(rowIndex) * 2 + (isResult ? 1 : 0))
    }

    /// Persisted `send_prompt_to_thread` calls on the calling conversation, each with its result,
    /// as the provider records them — Claude prefixed with the server name, Codex bare. An
    /// `unanswered` call is one still in flight, like the call being handled.
    func insertSendPromptCalls(
        to targetConversationID: String,
        count: Int,
        qualified: Bool = true,
        prompt: String = "Reply.",
        unanswered: Bool = false
    ) throws {
        let existing = try modelContext.fetchCount(FetchDescriptor<ConversationEventRecord>())
        let toolName = qualified
            ? AlvearyHostToolCatalog.qualifiedToolName(ThreadHostToolCatalog.sendPromptToThreadToolName)
            : ThreadHostToolCatalog.sendPromptToThreadToolName
        for offset in 0..<count {
            // A call and its result share one slot, so `existing` stays a row count for both helpers.
            let rowIndex = existing + offset * 2
            let toolID = "send-\(rowIndex)"
            modelContext.insert(ConversationEventRecord(
                conversationId: conversation.id,
                type: ConversationEventRecord.toolCallType,
                toolId: toolID,
                toolName: toolName,
                toolInput: "{\"thread_id\":\"\(targetConversationID)\",\"prompt\":\"\(prompt)\"}",
                timestamp: Self.transcriptTimestamp(rowIndex: rowIndex),
                conversation: conversation
            ))
            guard !unanswered else {
                continue
            }
            modelContext.insert(ConversationEventRecord(
                conversationId: conversation.id,
                type: ConversationEventRecord.toolResultType,
                toolId: toolID,
                toolOutput: "Sent.",
                timestamp: Self.transcriptTimestamp(rowIndex: rowIndex, isResult: true),
                conversation: conversation
            ))
        }
        try modelContext.save()
    }

    func sendPrompt(
        threadID: String,
        prompt: String,
        requestID: String = "request-1"
    ) async -> AgentCLIKit.AgentHostToolResult {
        await service.handle(
            context: agentContext(requestID: requestID),
            call: AgentCLIKit.AgentHostToolCall(
                name: ThreadHostToolCatalog.sendPromptToThreadToolName,
                arguments: ["thread_id": .string(threadID), "prompt": .string(prompt)]
            )
        )
    }
}
